use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::thread::sleep;
use std::time::Duration;

// philosopher can think or eat
struct Philosopher {
    name: String,
    left_fork: usize,
    right_fork: usize,
}

impl Philosopher {
    fn new(name: &str, left_fork: usize, right_fork: usize) -> Philosopher {
        Philosopher {
            name: String::from(name),
            left_fork,
            right_fork,
        }
    }

    fn run(&self, forks: &Vec<Mutex<Fork>>, referee: &Semaphore) {
        self.think();
        referee.acquire();
        self.eat(forks);
        referee.release();
    }

    fn eat(&self, forks: &Vec<Mutex<Fork>>) {
        let mutex_izq = forks.get(self.left_fork);
        let izq = mutex_izq.unwrap().lock().unwrap();
        println!("{} adquirio el izquierdo", self.name);
        sleep(Duration::from_millis(10));
        let mutex_der = forks.get(self.right_fork);
        let der = mutex_der.unwrap().lock().unwrap();
        println!("{} adquirio el derecho", self.name);

        println!("{} ESTA COMIENDO", self.name);
    }

    fn think(&self) {
        println!("{} ESTA PENSANDO", self.name);
        sleep(Duration::from_millis(10));
    }
}

struct Fork {}

struct Semaphore {
    counter: Mutex<usize>,
    cvar: Condvar,
}

impl Semaphore {
    fn new(counter: usize) -> Semaphore {
        Semaphore {
            counter: Mutex::new(counter),
            cvar: Condvar::new(),
        }
    }

    fn acquire(&self) {
        let mut counter = self.counter.lock().unwrap();
        // here we use a while to check again when notified
        while *counter == 0 {
            // here we already have the counter lock, we need to "free" the lock so other thread can make
            // the release() writing -=1. Meanwhile, here we should wait and recover the lock again when notified
            counter = self.cvar.wait(counter).unwrap();
        }
        *counter -= 1;
    }

    fn release(&self) {
        let mut counter = self.counter.lock().unwrap();
        *counter += 1;
        self.cvar.notify_one();
    }
}

fn main() {
    let forks = Arc::new(vec![
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
    ]);

    let philosophers = vec![
        Philosopher::new("Plato", 1, 0),
        Philosopher::new("Aristotle", 1, 2),
        Philosopher::new("Aquinas", 3, 2),
        Philosopher::new("Descartes", 4, 3),
        Philosopher::new("Locke", 0, 4),
    ];

    let referee = Arc::new(Semaphore::new(4)); //solo se sientan 4 en la mesa

    let mut handles = vec![];

    for p in philosophers {
        let forks = Arc::clone(&forks);
        let referee = Arc::clone(&referee);
        let handle = thread::spawn(move || {
            for _ in 0..100 {
                p.run(&forks, &referee)
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }
}
