import os from "node:os";
import path from "node:path";
console.log(os.userInfo().shell);
console.log(path.normalize("/bin/bash") === "/bin/bash");
console.log(path.normalize("/bin/bash"));
