use std::sync::{Arc, Mutex};
use std::thread;

pub struct Runway { id: u32, is_occupied: bool }

impl Runway {
    fn new(id: u32) -> Runway { Runway { id, is_occupied: false } }
}

pub struct Plane { id: u32 }
impl Plane {
    fn new(id: u32) -> Plane { Plane { id } }
}

pub struct Airport {
    runways: Mutex<Vec<Runway>>,
}

impl Airport {
    // Airport methods
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