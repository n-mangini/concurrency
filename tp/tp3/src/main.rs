use std::io::Read;
use std::io::Write;
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::sync::mpsc;
use std::sync::mpsc::Receiver;

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

type Job = Box<dyn FnOnce() + Send + 'static>;

struct ThreadPool(i32, Receiver<Job>);

impl ThreadPool {
    fn new(pool_size: i32, receiver_channel: Receiver<Job>) -> ThreadPool {
        todo!()
    }
}

fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();

    // El main thread crea el canal (la cola FIFO)
    let (sender, receiver) = std::sync::mpsc::channel::<Job>();

    // Le pasamos el receptor a la pool
    let pool = ThreadPool::new(20, receiver);

    for stream in listener.incoming() {
        let stream = stream.unwrap();

        let job = Box::new(move || {
            handle_client(stream);
        });

        // El main envía directamente el mensaje
        sender.send(job).unwrap();
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
