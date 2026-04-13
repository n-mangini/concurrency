use std::io::Read;
use std::io::Write;
use std::net::{TcpListener, TcpStream};
use std::thread;

fn handle_client(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    let read_bytes = stream.read(&mut buffer).unwrap();
    let request_str = String::from_utf8_lossy(&buffer[..read_bytes]);
    let first_line = request_str.lines().next().unwrap();
    let req_parts: Vec<&str> = first_line.split_whitespace().collect();
    let path = req_parts[1];
    let iterations: &str = path.split('/').last().unwrap();

    let response = format!(
        "HTTP/1.1 200 OK\r\n\r\nValor de pi: {}\n",
        calculate_pi(iterations.parse().unwrap())
    );

    stream.write_all(response.as_bytes()).unwrap();
}

fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    let mut pool = Vec::new();
    let POOL_LIMIT = 20;

    // accept connections and process them serially

    for stream in listener.incoming() {
        if pool.len() < POOL_LIMIT {
            pool.push(POOL_LIMIT);
            thread::spawn(|| handle_client(stream.unwrap()));
        }
        else {
            handle_client(stream.unwrap());
        }
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
