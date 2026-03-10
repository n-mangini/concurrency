use std::io::Read;
use std::net::{TcpListener, TcpStream};

fn handle_client(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    let read_bytes = stream.read(&mut buffer).unwrap();
    let request_str = String::from_utf8_lossy(&buffer[..read_bytes]);
    println!("{:?}", request_str);
}

fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("0.0.0.0:8080").unwrap();

    // accept connections and process them serially
    for stream in listener.incoming() {
        handle_client(stream?);
    }
    Ok(())
}

fn calculate_pi(i: u64) -> f64 {
    let mut suma = 0.0;
    for k in 0..i {
        let denominador = (2 * k + 1) as f64;
        let termino = 1.0 / denominador;
        if k % 2 == 0 {
            suma += termino;
        } else {
            suma -= termino;
        }
    }
    4.0 * suma
}