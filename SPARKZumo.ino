#include <main_loop.h>
#include <main_setup.h>


void sei_wrapper() {
  sei();
}

void Serial_Print(char* msg) {
    Serial.print(msg);
}

void setup() {	
  Serial.begin(9600);
  main_setup__setup();
}

void loop() {
  main_loop__mainloop();
}
