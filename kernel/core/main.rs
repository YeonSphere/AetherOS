#![no_std]
#![no_main]
#![feature(asm)]

use core::panic::PanicInfo;

mod memory;
mod process;
mod ipc;
mod hal;

/// Kernel entry point
#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Initialize hardware abstraction layer
    hal::init();

    // Initialize memory management
    memory::init();

    // Initialize process management
    process::init();

    // Initialize IPC
    ipc::init();

    // Start system services
    start_services();

    // Enter main kernel loop
    kernel_main();
}

/// Main kernel loop
fn kernel_main() -> ! {
    loop {
        // Handle interrupts
        hal::handle_interrupts();

        // Schedule processes
        process::schedule();

        // Process IPC messages
        ipc::process_messages();

        // Handle hardware events
        hal::process_events();
    }
}

/// Start essential system services
fn start_services() {
    // Initialize file system service
    services::fs::init();

    // Initialize network service
    services::net::init();

    // Initialize device management
    services::device::init();

    // Initialize security service
    services::security::init();
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
