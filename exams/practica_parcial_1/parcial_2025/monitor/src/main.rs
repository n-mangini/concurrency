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
    runway_available: Condvar,
}

impl Airport {
    fn new(runways: Vec<Runway>) -> Airport {
        Airport {
            runways: Mutex::new(runways),
            runway_available: Condvar::new(),
        }
    }

    fn request_runway(&self) -> u32 {
        let mut runways = self.runways.lock().unwrap();
        // chequea si todas las pistas estan ocupadas
        while runways.iter().all(|r| r.is_occupied) {
            //hacemos un wait, y al pasarle el lock, lo que hacemos es liberarlo hasta que se despierta
            // asignamos el wait a runways para que el lock se guarde en la variable original
            runways = self.runway_available.wait(runways).unwrap();
        }

        let found_runway = runways.iter_mut().find(|r| !r.is_occupied).unwrap();
        found_runway.is_occupied = true;
        found_runway.id
    }

    fn release_runway(&self, runway_id: u32) {
        let mut runways = self.runways.lock().unwrap();
        if let Some(runway) = runways.iter_mut().find(|r| r.id == runway_id) {
            runway.is_occupied = false;
            //self.runway_available.notify_all()
            // Si queremos dar prioridad a ciertos aviones, deberiamos hacer un notify_one() que notifique
            //a los de mayor prioridad
            self.runway_available.notify_one()
        }
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
