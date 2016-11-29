/*:

# Serial pipelines

> This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme. If you're seeing "no such module 'CwlSignal'" errors read the "Introduction" page for more details.

---

## A brief demonstration of CwlSignal
 */

import CwlSignal

let (i, o) = Signal<Int>.createPair()

// Transform into signal that emits a number of "Beep"s equal to the integer received
let endpoint = o.transform { (result: Result<Int>, next: SignalNext<String>) in
   switch result {
   case .success(let intValue): (0..<intValue).forEach { _ in next.send(value: "Beep") }
   case .failure(let error): next.send(error: error)
   }
}.subscribeValues { value in
   print(value)
}

i.send(value: 3)

// Make sure the endpoint stays alive (normally you'd store it in the surrounding scope)
withExtendedLifetime(endpoint) {}

