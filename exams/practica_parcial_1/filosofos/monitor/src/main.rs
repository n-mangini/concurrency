use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::thread::sleep;
use std::time::Duration;

// philosopher can think or eat
struct Philosopher {
    chair: usize,
    name: String,
}

impl Philosopher {
    fn new(chair: usize, name: &str) -> Philosopher {
        Philosopher {
            chair,
            name: String::from(name),
        }
    }

    fn run(&self, monitor: &TableMonitor) {
        self.think();
        monitor.take_forks(self.chair);
        self.eat();
        monitor.release_forks(self.chair);
    }

    fn eat(&self) {
        println!("{} ESTA COMIENDO", self.name);
    }

    fn think(&self) {
        println!("{} ESTA PENSANDO", self.name);
        sleep(Duration::from_millis(10));
    }
}

struct Fork {}

struct TableMonitor {
    states: Mutex<Vec<PhilosopherState>>,
    cvar: Condvar,
}

impl TableMonitor {
    fn new(states: Mutex<Vec<PhilosopherState>>, cvar: Condvar) -> TableMonitor {
        TableMonitor { states, cvar }
    }

    fn take_forks(&self, i: usize) {
        let mut states = self.states.lock().unwrap();
        states[i] = PhilosopherState::Hungry;

        // Calculamos quiénes son los vecinos
        let left = (i + 4) % 5;
        let right = (i + 1) % 5;

        // Aquí es donde el filósofo decide si debe esperar o no
        while states[left] == PhilosopherState::Eating || states[right] == PhilosopherState::Eating
        {
            // Si algún vecino está comiendo, soltamos el lock y esperamos 🛌
            states = self.cvar.wait(states).unwrap();
        }

        states[i] = PhilosopherState::Eating; // ¡Finalmente puede comer! 🍝
        println!("Filósofo {} está comiendo", i);
    }

    fn release_forks(&self, i: usize) {
        let mut states = self.states.lock().unwrap();
        states[i] = PhilosopherState::Thinking;
        self.cvar.notify_all();
    }
}

#[derive(PartialEq, Clone, Copy, Debug)]
enum PhilosopherState {
    Hungry,
    Eating,
    Thinking,
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
        Philosopher::new(0, "Plato"),
        Philosopher::new(1, "Aristotle"),
        Philosopher::new(2, "Aquinas"),
        Philosopher::new(3, "Descartes"),
        Philosopher::new(4, "Locke"),
    ];

    let mut threads = vec![];

    let initial_states = vec![
        PhilosopherState::Thinking,
        PhilosopherState::Thinking,
        PhilosopherState::Thinking,
        PhilosopherState::Thinking,
        PhilosopherState::Thinking,
    ];

    // Creamos el monitor envuelto en un Arc para compartirlo
    let monitor = Arc::new(TableMonitor::new(
        Mutex::new(initial_states),
        Condvar::new(),
    ));

    for p in philosophers {
        let monitor = monitor.clone();
        let handle = thread::spawn(move || {
            for _ in 0..100 {
                p.run(&monitor);
            }
        });
        threads.push(handle);
    }

    for handle in threads {
        handle.join().unwrap();
    }
}
