use std::sync::{Arc, Condvar, Mutex};
use std::thread;

pub struct Runway {
    id: usize,
    is_occupied: bool,
    conflict_ids: Vec<usize>,
}

impl Runway {
    fn new(id: usize, conflict_ids: Vec<usize>) -> Runway {
        Runway {
            id,
            is_occupied: false,
            conflict_ids,
        }
    }
}

pub struct Plane {
    id: usize,
}

impl Plane {
    fn new(id: usize) -> Plane {
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

    fn request_runway(&self) -> usize {
        let mut runways = self.runways.lock().unwrap();
        // El caso desfavorable lo planteamos como el caso favorable negado
        // Cuando PUEDO atterizar? -> Cuando hay alguna pista libre y esa pista no tiene conflicts
        while !runways.iter().any(|r| {
            !r.is_occupied
                && r.conflict_ids
                    .iter()
                    .all(|&id| !runways.iter().any(|p| p.id == id && p.is_occupied))
        }) {
            runways = self.runway_available.wait(runways).unwrap();
        }

        // agarramos esa misma pista que nos hizo salir del while
        // buscamos su posicion en el array con un interador inmutable
        let found_runway_index = runways.iter().position(|r| {
            !r.is_occupied
                && r.conflict_ids
                .iter()
                .all(|&id| !runways.iter().any(|p| p.id == id && p.is_occupied))
        }).unwrap();

        runways[found_runway_index].is_occupied = true;
        runways[found_runway_index].id
    }

    fn release_runway(&self, runway_id: usize) {
        let mut runways = self.runways.lock().unwrap();
        if let Some(runway) = runways.iter_mut().find(|r| r.id == runway_id) {
            runway.is_occupied = false;
            //self.runway_available.notify_all()
            self.runway_available.notify_all()
        }
    }
}

fn main() {
    // Create the runways, the planes, and the airport
    let runway_13 = Runway::new(13, vec![31]);
    let runway_31 = Runway::new(31, vec![13]);
    let runways = vec![runway_13, runway_31];
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
