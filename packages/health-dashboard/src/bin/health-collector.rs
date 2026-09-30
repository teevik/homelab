fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 || args[1] != "--config" {
        eprintln!("usage: health-collector --config PATH");
        std::process::exit(2);
    }
    if let Err(error) = health_dashboard::collector::run(std::path::Path::new(&args[2])) {
        eprintln!("health-collector: {error}");
        std::process::exit(1);
    }
}
