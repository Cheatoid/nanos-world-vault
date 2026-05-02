// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

// Anti-Cheat Detection Worker

let devtoolsOpen = false;

// Debugger trick with eval - obfuscated timing check
const checkDebugger = () => {
	const start = performance.now();
	try {
		eval('debugger');
	} catch (e) {
		// Debugger statement in eval
	}
	const elapsed = performance.now() - start;
	if (elapsed > 100) {
		devtoolsOpen = true;
		postMessage({type: 'TRIGGER', cause: 'Debugger timing attack (elapsed: ' + elapsed.toFixed(2) + 'ms)'});
	}
	// Random interval between 500ms and 2000ms
	const randomDelay = Math.floor(Math.random() * 1500) + 500;
	setTimeout(checkDebugger, randomDelay);
};

// Monitor critical operations with random timing checks
const monitorExecution = () => {
	const start = performance.now();
	// Simulate a complex operation
	let dummy = 0;
	for (let i = 0; i < 1000; i++) {
		dummy += Math.random();
	}
	const elapsed = performance.now() - start;
	if (elapsed > 10) {
		postMessage({type: 'TRIGGER', cause: 'Execution monitoring detected slowdown (' + elapsed.toFixed(2) + 'ms)'});
	}
	// Random interval for next check
	setTimeout(monitorExecution, Math.floor(Math.random() * 3000) + 2000);
};

// Element inspection detection
const element = new Image();
Object.defineProperty(element, 'id', {
	get: function () {
		postMessage({type: 'TRIGGER', cause: 'Element inspection detection'});
	}
});

// Console timing attack
const t0 = Date.now();
console.log('%c', t0);
console.log('%c', Date.now());
const t1 = Date.now();
if (t1 - t0 > 100) {
	postMessage({type: 'TRIGGER', cause: 'Console timing attack (elapsed: ' + (t1 - t0) + 'ms)'});
}

// Start detection with random delays
setTimeout(checkDebugger, Math.floor(Math.random() * 1000));
setTimeout(monitorExecution, Math.floor(Math.random() * 2000));
