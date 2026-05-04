use std::sync::{Arc, Mutex};
use std::thread;
use std::thread::sleep;
use std::time::Duration;

// philosopher can think or eat
struct Philosopher {
    name: String,
    left_fork: usize,
    right_fork: usize,
    eats: usize,
}

struct Fork {}

impl Philosopher {
    fn new(name: &str, left_fork: usize, right_fork: usize) -> Philosopher {
        Philosopher {
            name: String::from(name),
            left_fork,
            right_fork,
            eats: 0,
        }
    }

    fn run(&self, forks: &Vec<Mutex<Fork>>) {
        self.think();
        self.eat(forks);
    }

    fn eat(&self, forks: &Vec<Mutex<Fork>>) {
        /*println!("{} esta intentando comer", self.name);*/
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
        /*        if self.name == "Descartes" {
            println!("pienso luego existo");
            sleep(Duration::new(2, 0));
        } else {*/
        println!("{} ESTA PENSANDO", self.name);
        sleep(Duration::from_millis(10));
        /*        }*/
    }
}

fn main() {
    /*    let mut forks = Vec::new();
    forks.push(Fork {});
    forks.push(Fork {});
    forks.push(Fork {});
    forks.push(Fork {});
    forks.push(Fork {});*/
    let forks = Arc::new(vec![
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
        Mutex::new(Fork {}),
    ]);

    // Una forma de solucionar el problema del deadlock es que uno de los filosofos_deadlock
    // agarre primero el de su derecha, pero de ese modo no estamos siendo justos
    // , es decir, no cumplimos el concepto de fairness, y ademas tenemos starvation,
    // ya que uno de ellos se puede quedar esperando
    let philosophers = vec![
        Philosopher {
            name: String::from("Plato"),
            left_fork: 1,
            right_fork: 0,
            eats: 0,
        },
        Philosopher {
            name: String::from("Aristotle"),
            left_fork: 1,
            right_fork: 2,
            eats: 0,
        },
        Philosopher {
            name: String::from("Aquinas"),
            left_fork: 3,
            right_fork: 2,
            eats: 0,
        },
        Philosopher {
            name: String::from("Descartes"),
            left_fork: 4,
            right_fork: 3,
            eats: 0,
        },
        Philosopher {
            name: String::from("Locke"),
            left_fork: 0,
            right_fork: 4,
            eats: 0,
        },
    ];

    let mut handles = vec![];

    for p in philosophers {
        let forks = Arc::clone(&forks);
        // Intentamos que cada hilo use 'forks'
        let handle = thread::spawn(move || {
            for _ in 0..100 {
                p.run(&forks)
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }
}
