use std::sync::{Arc, Condvar, Mutex};
use std::thread;

pub struct Runway {
    id: u32,
    is_occupied: bool,
}

impl Runway {
    fn new(id: u32) -> Runway {
        Runway {
            id,
            is_occupied: false,
        }
    }
}

pub struct Plane {
    id: u32,
}

impl Plane {
    fn new(id: u32) -> Plane {
        Plane { id }
    }
}

pub struct Airport {
    // one runway used at a time -> mutual exclusion
    runways: Mutex<Vec<Runway>>,
    semaphore: Semaphore,
}

impl Airport {
    fn new(runways: Vec<Runway>) -> Airport {
        let runways_amount = runways.len();
        Airport {
            runways: Mutex::new(runways),
            semaphore: Semaphore::new(runways_amount)
        }
    }

    fn request_runway(&self) -> u32 {
        self.semaphore.acquire();

        let mut runways = self.runways.lock().unwrap();
        let found_runway = runways.iter_mut().find(|r| !r.is_occupied).unwrap();
        found_runway.is_occupied = true;
        found_runway.id
    }

    fn release_runway(&self, runway_id: u32) {
        let mut runways = self.runways.lock().unwrap();
        if let Some(runway) = runways.iter_mut().find(|r| r.id == runway_id) {
            runway.is_occupied = false;
        }
        self.semaphore.release();
    }
}

struct Semaphore {
    counter: Mutex<usize>,
    cvar: Condvar,
}

impl Semaphore {
    fn new(initial_value: usize) -> Semaphore {
        Semaphore {
            counter: Mutex::new(initial_value),
            cvar: Condvar::new(),
        }
    }

    fn acquire(&self) {
        let mut counter = self.counter.lock().unwrap();

        while *counter == 0 {
            counter = self.cvar.wait(counter).unwrap()
        }
        *counter -= 1;
    }

    fn release(&self) {
        let mut counter = self.counter.lock().unwrap();
        *counter += 1;
        self.cvar.notify_one()
    }
}

fn main() {
    // Create the runways, the planes, and the airport
    let runways = (0..3).map(|i| Runway::new(i)).collect();
    let planes = (0..10).map(|i| Plane::new(i));
    let arc_airport = Arc::new(Airport::new(runways));
    // Launch one thread per plane
    thread::scope(|s| {
        for plane in planes {
            let airport = arc_airport.clone();
            let plane_id = plane.id;
            s.spawn(move || {
                println!("Plane {}, requesting landing", plane_id);
                let runway_id = airport.request_runway();
                println!("Plane {}, landing on runway {}", plane_id, runway_id);
                thread::sleep(std::time::Duration::from_secs(1));
                println!("Plane {}, landed", plane_id);
                airport.release_runway(runway_id);
            });
        }
    });
}
