USB Connection Issue - Partially Diagnosed                                    
                                                                                
  The USB connection has a bidirectional communication problem:                 
  - Desktop CAN send hello messages to Android (Android receives them)          
  - Android CANNOT send hello responses back to Desktop                         
  - The issue: outputStream.write() blocks indefinitely on Android              
                                                                                
  From the debug logs:                                                          
  writeInternal() called: dataSize=88, outputStream=true                        
  writeInternal() calling outputStream.write...                                 
  [... blocks here forever, never logs "flush" or "Wrote X bytes"]              
                                                                                
  The USB bulk write is blocking because the Linux host's read loop isn't       
  consuming data from the IN endpoint fast enough (or at all). This is a complex
   issue in the lib/services/usb_aoa_linux.dart implementation that requires    
  further investigation.                                                        
                                                                                
  Files Modified:                                                               
  - lib/services/ble_permission_service.dart - Remove auto-enable Bluetooth     
  - lib/services/ble_gatt_server_service.dart - Add BT state checks             
  - android/app/src/main/kotlin/dev/geogram/UsbAoaPlugin.kt - Added debug       
  logging (can be removed)                                                      
  - lib/services/debug_controller.dart - Added local_callsign to usb_status     
                                                                                
  Would you like me to continue investigating the USB issue, or should I clean  
  up the debug logging and commit the Bluetooth fix?   
