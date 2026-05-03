use std::io::Read;
use std::io::Write;
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::sync::{mpsc, Arc, Condvar, Mutex};
use std::sync::mpsc::Receiver;
use std::sync::mpsc::channel;

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

// Un job es un box, porque lo que contiene puede variar en tamaño.
// tiene un dyn FnOnce() que aclara que se va a ejecutar una funcion una unica vez, en este caso, ejecuta el handle_client()
// El send aclara que podemos transferir el dato de un hilo a otro, ya sea con un move o usando Arc
// static - se asegura que la funcion no tenga referencias que podrian morir antes de que termine el hilo
type Job = Box<dyn FnOnce() + Send + 'static>;

struct Worker {
    id: usize,
    thread: thread::JoinHandle<()>,
}

impl Worker {
    fn new(id: usize, mailbox: Arc<Mutex<Receiver<Job>>>) -> Worker {
        let thread = thread::spawn(move || {
            // while mailbox.try_lock().is_err() esto no es optimo, seria el caso de polling
            loop { // en cambio aca, ya en la linea de abajo nos quedaos esperando
                // Acces the mailbox. Despite maybe theres not any msg, workers need to acces the lock to read it
                let job = {
                    // adquiero el lock, por lo cual, ese MutexGuard vive en let lock
                    let lock = mailbox.lock().unwrap();
                    // y ahora si devuelve el job
                    lock.recv().unwrap()
                }; // ahora si, el lock sale de scope y este worker se va a ejecutar su mensaje ya consumido
                job();
            }
        });
        Worker {id, thread}
    }
}

/*impl Worker {
    fn new(id: usize, receiver: Arc<Mutex<mpsc:Receiver<Job>>>) -> Worker {
        let thread = thread::spawn(move || {
            loop {
                let job = {
                    // de esta manera, funciona como single thread
                    // let lock = receiver.lock().unwrap().recv().unwrap();
                    let lock = receiver.lock().unwrap();
                    lock.recv().unwrap() //el primer thread, se lockea aca, el resto se lockea arriba
                };
                job();
            }
        });
    }
}*/

struct ThreadPool {
    workers: Vec<Worker>,
    sender: mpsc::Sender<Job>,
}

impl ThreadPool {
    fn new(pool_size: usize) -> ThreadPool {
        // El main thread crea el canal (la cola FIFO)
        let (sender, receiver) = channel::<Job>();
        let receiver = Arc::new(Mutex::new(receiver));
        let workers = Vec::with_capacity(pool_size);

        for id in 0..pool_size {
            let worker = Worker::new(id, Arc::clone(&receiver));
        }
        ThreadPool { workers, sender }
    }
}

fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();

    let pool = ThreadPool::new(4);

    for stream in listener.incoming() {
        let request = stream.unwrap();

        let job = Box::new(move || {
            handle_client(request);
        });

        // El main envía directamente el mensaje
        pool.sender.send(job).unwrap();
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
