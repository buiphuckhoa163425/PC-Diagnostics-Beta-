
use serde::{Deserialize, Serialize};
use std::net::{TcpStream, ToSocketAddrs};
use std::process::Command;
use std::time::{Duration, Instant};
use sysinfo::{CpuRefreshKind, Disks, RefreshKind, System};
use wmi::WMIConnection;

#[derive(Serialize)]
struct CpuInfo {
    name: String,
    frequency_mhz: u64,
    core_count: usize,
    manufacturer: Option<String>,
    processor_id: Option<String>,
    cpuid_name: Option<String>,
    verification_status: String,
}

#[derive(Serialize)]
struct MemoryInfo {
    total_mb: u64,
    used_mb: u64,
    available_mb: u64,
}

#[derive(Serialize)]
struct StorageInfo {
    name: String,
    mount_point: String,
    total_gb: u64,
    available_gb: u64,
}

#[derive(Serialize)]
struct GpuInfo {
    name: String,
    vram_mb: Option<u64>,
}

#[derive(Serialize)]
struct BatteryInfo {
    detected: bool,
    charge_percent: Option<u16>,
    estimated_runtime_minutes: Option<u32>,
}

#[derive(Serialize)]
struct BiosInfo {
    manufacturer: Option<String>,
    version: Option<String>,
    release_date: Option<String>,
}

#[derive(Serialize)]
struct ComputerInfo {
    manufacturer: Option<String>,
    model: Option<String>,
}


#[derive(Serialize)]
struct NetworkCheck {
    name: String,
    status: String,
    target: String,
    latency_ms: Option<u128>,
    detail: String,
}

#[derive(Serialize)]
struct NetworkInfo {
    checks: Vec<NetworkCheck>,
    overall_status: String,
    vpn_warning: String,
    note: String,
}

#[derive(Serialize)]
struct Diagnostics {
    cpu: CpuInfo,
    memory: MemoryInfo,
    storage: Vec<StorageInfo>,
    gpu: Vec<GpuInfo>,
    battery: BatteryInfo,
    bios: BiosInfo,
    computer: ComputerInfo,
    network: NetworkInfo,
}

#[derive(Deserialize)]
struct Processor {
    #[serde(rename = "Name")]
    name: Option<String>,
    #[serde(rename = "Manufacturer")]
    manufacturer: Option<String>,
    #[serde(rename = "ProcessorId")]
    processor_id: Option<String>,
    #[serde(rename = "NumberOfCores")]
    number_of_cores: Option<u32>,
    #[serde(rename = "CurrentClockSpeed")]
    current_clock_speed: Option<u32>,
}

#[derive(Deserialize)]
struct VideoController {
    #[serde(rename = "Name")]
    name: Option<String>,
    #[serde(rename = "AdapterRAM")]
    adapter_ram: Option<u64>,
}

#[derive(Deserialize)]
struct Battery {
    #[serde(rename = "EstimatedChargeRemaining")]
    charge_remaining: Option<u16>,
    #[serde(rename = "EstimatedRunTime")]
    estimated_runtime: Option<u32>,
}

#[derive(Deserialize)]
struct BiosRecord {
    #[serde(rename = "Manufacturer")]
    manufacturer: Option<String>,
    #[serde(rename = "SMBIOSBIOSVersion")]
    version: Option<String>,
    #[serde(rename = "ReleaseDate")]
    release_date: Option<String>,
}

#[derive(Deserialize)]
struct ComputerRecord {
    #[serde(rename = "Manufacturer")]
    manufacturer: Option<String>,
    #[serde(rename = "Model")]
    model: Option<String>,
}

fn clean(value: Option<String>) -> Option<String> {
    value
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn normalize_cpu_name(name: &str) -> String {
    name.to_lowercase()
        .replace("(r)", "")
        .replace("(tm)", "")
        .replace("®", "")
        .replace("™", "")
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect()
}

#[cfg(target_arch = "x86_64")]
fn get_cpuid_brand() -> Option<String> {
    use std::arch::x86_64::__cpuid;

    // CPUID brand string: extended leaves 0x80000002–0x80000004.
    let max_leaf = __cpuid(0x80000000).eax;

    if max_leaf < 0x80000004 {
        return None;
    }

    let mut bytes = Vec::with_capacity(48);

    for leaf in 0x80000002..=0x80000004 {
        let result = __cpuid(leaf);

        for value in [result.eax, result.ebx, result.ecx, result.edx] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
    }

    let brand = String::from_utf8_lossy(&bytes).trim().to_string();

    if brand.is_empty() {
        None
    } else {
        Some(brand)
    }
}

#[cfg(not(target_arch = "x86_64"))]
fn get_cpuid_brand() -> Option<String> {
    None
}

fn compare_cpu_names(wmi_name: &str, cpuid_name: Option<&str>) -> String {
    let Some(cpuid_name) = cpuid_name else {
        return "UNVERIFIED".to_string();
    };

    let wmi = normalize_cpu_name(wmi_name);
    let cpuid = normalize_cpu_name(cpuid_name);

    if wmi.is_empty() || cpuid.is_empty() {
        return "UNVERIFIED".to_string();
    }

    if wmi == cpuid || wmi.contains(&cpuid) || cpuid.contains(&wmi) {
        "CONSISTENT".to_string()
    } else {
        "MISMATCH".to_string()
    }
}


fn check_tcp(name: &str, host: &str, port: u16, timeout: Duration) -> NetworkCheck {
    let target = format!("{host}:{port}");
    let start_dns = Instant::now();
    let resolved = (host, port).to_socket_addrs();

    let addresses: Vec<_> = match resolved {
        Ok(iter) => iter.collect(),
        Err(error) => {
            return NetworkCheck {
                name: name.to_string(),
                status: "FAILED".to_string(),
                target,
                latency_ms: None,
                detail: format!("DNS resolution failed: {error}"),
            };
        }
    };

    if addresses.is_empty() {
        return NetworkCheck {
            name: name.to_string(),
            status: "FAILED".to_string(),
            target,
            latency_ms: None,
            detail: "DNS returned no addresses.".to_string(),
        };
    }

    let dns_ms = start_dns.elapsed().as_millis();
    let mut last_error = String::from("No address responded.");
    for address in addresses {
        let start = Instant::now();
        match TcpStream::connect_timeout(&address, timeout) {
            Ok(stream) => {
                let latency = start.elapsed().as_millis();
                drop(stream);
                return NetworkCheck {
                    name: name.to_string(),
                    status: "PASS".to_string(),
                    target,
                    latency_ms: Some(latency),
                    detail: format!("TCP connection succeeded; DNS lookup took about {dns_ms} ms. This is TCP connection time, not ICMP ping."),
                };
            }
            Err(error) => last_error = error.to_string(),
        }
    }

    NetworkCheck {
        name: name.to_string(),
        status: "FAILED".to_string(),
        target,
        latency_ms: None,
        detail: format!("TCP connection failed or timed out: {last_error}. This alone does not prove the Internet is disconnected; the endpoint or port may be blocked."),
    }
}

fn run_network_diagnostics() -> NetworkInfo {
    let timeout = Duration::from_secs(3);
    let checks = vec![
        check_tcp("Cloudflare HTTPS endpoint", "1.1.1.1", 443, timeout),
        check_tcp("Google HTTPS endpoint", "www.google.com", 443, timeout),
        check_tcp("Speedtest.net HTTPS endpoint", "www.speedtest.net", 443, timeout),
    ];

    let internet_ok = checks.iter().any(|c| c.status == "PASS" && c.name != "Speedtest.net HTTPS endpoint");
    let speedtest_ok = checks.iter().any(|c| c.name == "Speedtest.net HTTPS endpoint" && c.status == "PASS");
    let overall_status = if internet_ok && speedtest_ok {
        "PASS"
    } else if internet_ok && !speedtest_ok {
        "PARTIAL"
    } else if checks.iter().all(|c| c.status == "FAILED") {
        "FAILED"
    } else {
        "PARTIAL"
    };

    NetworkInfo {
        checks,
        overall_status: overall_status.to_string(),
        vpn_warning: "VPN can increase latency (ping) and reduce download/upload speed because traffic may take a longer route and pass through an extra server. It can sometimes improve routing. Compare tests with VPN off and on; only use a VPN if permitted by your network policy.".to_string(),
        note: "This first version tests DNS resolution and TCP connectivity to HTTPS port 443. It does not measure download/upload throughput or ICMP ping, and a failed endpoint does not by itself mean the Internet is disconnected.".to_string(),
    }
}


// Fixed allowlist: no user-supplied shell command is ever executed.
fn integrity_action(action: &str) {
    let (program, arguments, repairs): (&str, &[&str], bool) = match action {
        "scan-sfc" => ("sfc.exe", &["/verifyonly"], false),
        "scan-dism" => ("dism.exe", &["/Online", "/Cleanup-Image", "/ScanHealth"], false),
        "repair-sfc" => ("sfc.exe", &["/scannow"], true),
        "repair-dism" => ("dism.exe", &["/Online", "/Cleanup-Image", "/RestoreHealth"], true),
        _ => {
            println!("{}", serde_json::json!({"ok":false,"error":"Unsupported integrity action"}));
            return;
        }
    };
    let admin = Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-Command",
            "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"])
        .output()
        .ok()
        .map(|o| o.status.success() && String::from_utf8_lossy(&o.stdout).trim().eq_ignore_ascii_case("true"))
        .unwrap_or(false);
    if !admin {
        println!("{}", serde_json::json!({"ok":false,"action":action,
            "error":"Administrator permission required. Close and reopen PC Diagnostics as administrator, then retry."}));
        return;
    }
    match Command::new(program).args(arguments).output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            println!("{}", serde_json::json!({
                "ok":output.status.success(),"action":action,"repair":repairs,
                "exit_code":output.status.code(),"stdout":stdout,"stderr":stderr,
                "note":"Exit code and output must be reviewed; success does not guarantee the machine is fully repaired."
            }));
        }
        Err(error) => println!("{}", serde_json::json!({
            "ok":false,"action":action,"error":format!("Unable to launch system tool: {error}")
        })),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 {
        if args.len() == 3 && args[1] == "--integrity" {
            integrity_action(&args[2]);
        } else {
            println!("{}", serde_json::json!({"ok":false,"error":"Unsupported arguments"}));
        }
        return;
    }
    let mut system = System::new_with_specifics(
        RefreshKind::nothing()
            .with_cpu(CpuRefreshKind::everything()),
    );

    system.refresh_cpu_all();
    system.refresh_memory();

    let wmi = WMIConnection::new().ok();

    // CPU: ưu tiên tên model từ Windows WMI, không dùng "CPU 1".
    let processors: Vec<Processor> = match &wmi {
        Some(connection) => connection
            .raw_query(
                "SELECT Name, Manufacturer, ProcessorId, NumberOfCores, CurrentClockSpeed \
                 FROM Win32_Processor",
            )
            .unwrap_or_default(),
        None => Vec::new(),
    };

    let first_processor = processors.first();

    let cpuid_name = get_cpuid_brand();

    let cpu_name = first_processor
        .and_then(|p| clean(p.name.clone()))
        .or_else(|| cpuid_name.clone())
        .unwrap_or_else(|| "Unknown".to_string());

    let frequency_mhz = first_processor
        .and_then(|p| p.current_clock_speed)
        .map(u64::from)
        .filter(|frequency| *frequency > 0)
        .or_else(|| {
            system.cpus()
                .first()
                .map(|cpu| cpu.frequency())
                .filter(|frequency| *frequency > 0)
        })
        .unwrap_or(0);

    let core_count = first_processor
        .and_then(|p| p.number_of_cores)
        .map(|count| count as usize)
        .filter(|count| *count > 0)
        .unwrap_or_else(|| {
            system.cpus().len()
        });

    let verification_status = first_processor
        .and_then(|p| clean(p.name.clone()))
        .map(|name| compare_cpu_names(&name, cpuid_name.as_deref()))
        .unwrap_or_else(|| "UNVERIFIED".to_string());

    let cpu = CpuInfo {
        name: cpu_name,
        frequency_mhz,
        core_count,
        manufacturer: first_processor
            .and_then(|p| clean(p.manufacturer.clone())),
        processor_id: first_processor
            .and_then(|p| clean(p.processor_id.clone())),
        cpuid_name,
        verification_status,
    };

    // RAM
    let memory = MemoryInfo {
        total_mb: system.total_memory() / 1024 / 1024,
        used_mb: system.used_memory() / 1024 / 1024,
        available_mb: system.available_memory() / 1024 / 1024,
    };

    // Storage
    let disks = Disks::new_with_refreshed_list();

    let storage: Vec<StorageInfo> = disks
        .iter()
        .map(|disk| StorageInfo {
            name: disk.name().to_string_lossy().to_string(),
            mount_point: disk.mount_point().display().to_string(),
            total_gb: disk.total_space() / 1024 / 1024 / 1024,
            available_gb: disk.available_space() / 1024 / 1024 / 1024,
        })
        .collect();

    // GPU
    let mut gpu = Vec::new();

    if let Some(connection) = &wmi {
        let result: Result<Vec<VideoController>, _> = connection
            .raw_query(
                "SELECT Name, AdapterRAM FROM Win32_VideoController",
            );

        if let Ok(gpus) = result {
            for item in gpus {
                gpu.push(GpuInfo {
                    name: clean(item.name)
                        .unwrap_or_else(|| "Unknown".to_string()),
                    vram_mb: item.adapter_ram.map(|ram| ram / 1024 / 1024),
                });
            }
        }
    }

    // Battery: loại bỏ các giá trị runtime bất thường.
    let mut battery = BatteryInfo {
        detected: false,
        charge_percent: None,
        estimated_runtime_minutes: None,
    };

    if let Some(connection) = &wmi {
        let result: Result<Vec<Battery>, _> = connection
            .raw_query(
                "SELECT EstimatedChargeRemaining, EstimatedRunTime \
                 FROM Win32_Battery",
            );

        if let Ok(batteries) = result {
            if let Some(item) = batteries.first() {
                battery.detected = true;

                battery.charge_percent = item
                    .charge_remaining
                    .filter(|percent| *percent <= 100);

                battery.estimated_runtime_minutes = item
                    .estimated_runtime
                    .filter(|minutes| {
                        *minutes > 0 && *minutes != u32::MAX && *minutes <= 10080
                    });
            }
        }
    }

    // BIOS/UEFI information from SMBIOS via WMI.
    let bios = if let Some(connection) = &wmi {
        let records: Result<Vec<BiosRecord>, _> = connection
            .raw_query(
                "SELECT Manufacturer, SMBIOSBIOSVersion, ReleaseDate \
                 FROM Win32_BIOS",
            );

        records.ok()
            .and_then(|items| items.into_iter().next())
            .map(|item| BiosInfo {
                manufacturer: clean(item.manufacturer),
                version: clean(item.version),
                release_date: clean(item.release_date),
            })
            .unwrap_or(BiosInfo {
                manufacturer: None,
                version: None,
                release_date: None,
            })
    } else {
        BiosInfo {
            manufacturer: None,
            version: None,
            release_date: None,
        }
    };

    // Computer manufacturer and model from SMBIOS/WMI.
    let computer = if let Some(connection) = &wmi {
        let records: Result<Vec<ComputerRecord>, _> = connection
            .raw_query(
                "SELECT Manufacturer, Model FROM Win32_ComputerSystem",
            );

        records.ok()
            .and_then(|items| items.into_iter().next())
            .map(|item| ComputerInfo {
                manufacturer: clean(item.manufacturer),
                model: clean(item.model),
            })
            .unwrap_or(ComputerInfo {
                manufacturer: None,
                model: None,
            })
    } else {
        ComputerInfo {
            manufacturer: None,
            model: None,
        }
    };

    let diagnostics = Diagnostics {
        cpu,
        memory,
        storage,
        gpu,
        battery,
        bios,
        computer,
        network: run_network_diagnostics(),
    };

    match serde_json::to_string_pretty(&diagnostics) {
        Ok(json) => println!("{}", json),
        Err(error) => eprintln!("JSON error: {}", error),
    }
}