use std::thread;

fn hello () {
    let n = 10;
    let mut m = 10;
    thread::scope(|s| {
        s.spawn(|| {
            m = m + 1;
            println!("Hello from thread 1, n = {n}")
        });
        s.spawn(|| {println!("Hello from thread 2, n = {n}")});
    });
    println!("{m}");
}
