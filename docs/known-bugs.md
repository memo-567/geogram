# Known Bugs

## flutter_zxing Linux build failure (v1.9.1)

**Issue:** Linux build fails with `use of undeclared identifier 'uint8_t'` error.

**Error message:**
```
flutter_zxing/src/dart_alloc.h:114:28: error: use of undeclared identifier 'uint8_t'
flutter_zxing/src/dart_alloc.h:114:64: error: use of undeclared identifier 'uint8_t'
```

**Cause:** The header file `dart_alloc.h` is missing `#include <cstdint>` which defines `uint8_t`.

**Fix:** Add the missing include to the pub cache file:

```bash
# Find the file location
FILE="$HOME/.pub-cache/hosted/pub.dev/flutter_zxing-1.9.1/src/dart_alloc.h"

# Add #include <cstdint> after #pragma once
sed -i 's/#pragma once/#pragma once\n\n#include <cstdint>/' "$FILE"
```

Or manually edit `~/.pub-cache/hosted/pub.dev/flutter_zxing-1.9.1/src/dart_alloc.h` and add:

```cpp
#include <cstdint>
```

after `#pragma once` at the top of the file.

**Note:** Running `flutter pub get` may overwrite the pub cache and require reapplying this fix.

**Upstream:** Consider reporting this bug at https://github.com/khoren93/flutter_zxing/issues
