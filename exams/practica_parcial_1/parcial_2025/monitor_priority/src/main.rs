use std::collections::BinaryHeap;
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
    priority: u32,
}

impl Plane {
    fn new(id: u32, priority: u32) -> Plane {
        Plane { id, priority }
    }
}

// creamos este nuevo struct para evitar modificar una de las dos sin lockear la otra
pub struct AirportState {
    runways: Vec<Runway>,
    waiting_list: BinaryHeap<u32>,
}

pub struct Airport {
    state: Mutex<AirportState>,
    runway_available: Condvar,
}

impl AirportState {
    fn new (runways: Vec<Runway>) -> AirportState {
        AirportState {
            runways,
            waiting_list: BinaryHeap::new()
        }
    }
}

impl Airport {
    fn new(runways: Vec<Runway>) -> Airport {
        Airport {
            state: Mutex::new(AirportState::new(runways)),
            runway_available: Condvar::new(),
        }
    }

    fn request_runway(&self, priority: u32) -> u32 {
        let mut state = self.state.lock().unwrap();

        state.waiting_list.push(priority);

        // como sabemos adentro del while va el caso menos favorable
        // chequea si las pistas estan ocupadas o si alguien tiene mas prioridad que yo
        // solo salgo del while si ambas son falsas -> hay pista y tengo la maxima prioridad
        while state.runways.iter().all(|r| r.is_occupied) || *state.waiting_list.peek().unwrap() > priority {
            state = self.runway_available.wait(state).unwrap();
        }

        //dejo de esperar, asi que me salgo de la lista porque ahora paso a ocupar la pista
        state.waiting_list.pop();

        let found_runway_pos = state.runways.iter().position(|r| {
            !r.is_occupied && *state.waiting_list.peek().unwrap() == priority
        }).unwrap(); //unwrap porque estoy seguroq ue la voy a encontrar

        state.runways[found_runway_pos].is_occupied = true;
        state.runways[found_runway_pos].id
    }

    fn release_runway(&self, runway_id: u32) {
        let mut state = self.state.lock().unwrap();
        if let Some(runway) = state.runways.iter_mut().find(|r| r.id == runway_id) {
            runway.is_occupied = false;
            // aca la idea es avisar a todos, para que independiente de quien agarra el lock nuevamente, solo
            // gane el que tiene la prioridad mas alta del binary heap
            self.runway_available.notify_all()
        }
    }
}

fn main() {
    // Create the runways, the planes, and the airport
    let runways = (0..3).map(|i| Runway::new(i)).collect();
    // el segundo i es priority
    let planes = (0..10).map(|i| Plane::new(i, i));
    let arc_airport = Arc::new(Airport::new(runways));
    // Launch one thread per plane
    thread::scope(|s| {
        for plane in planes {
            let airport = arc_airport.clone();
            let plane_id = plane.id;
            s.spawn(move || {
                println!("Plane {}, requesting landing with priority {}", plane_id, plane.priority);
                let runway_id = airport.request_runway(plane.priority);
                println!("Plane {}, landing on runway {}", plane_id, runway_id);
                thread::sleep(std::time::Duration::from_secs(1));
                println!("Plane {}, landed", plane_id);
                airport.release_runway(runway_id);
            });
        }
    });
}
