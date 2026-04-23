// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

// Anti-Cheat Module

(function () {
	'use strict';

	// ================================================================
	// DEVELOPMENT: Uncomment this function to unban yourself, you fool
	// ================================================================
	function unbanUser() {
		try {
			// Clear cookie
			document.cookie = 'ac_banned=; path=/; max-age=0; SameSite=Strict; Secure';

			// Clear sessionStorage
			sessionStorage.removeItem('ac_banned');

			// Clear localStorage
			localStorage.removeItem('ac_banned');

			// Clear IndexedDB
			try {
				const request = indexedDB.open('anticheat_db', 1);
				request.onsuccess = (e) => {
					const db = e.target.result;
					if (db.objectStoreNames.contains('bans')) {
						const transaction = db.transaction(['bans'], 'readwrite');
						const store = transaction.objectStore('bans');
						store.delete(userHash);
					}
				};
			} catch (e) {
			}

			console.log('User unbanned successfully');
		} catch (e) {
			console.log('Error unbanning user:', e);
		}
	}

	// Uncomment to unban:
	unbanUser();

	// ============================================================
	// DEVELOPMENT: Uncomment to disable AntiCheat for development
	// ============================================================
	const DISABLE_ANTICHEAT = true;
	if (typeof DISABLE_ANTICHEAT !== 'undefined' && DISABLE_ANTICHEAT) {
		return;
	}

	// Origin check - only allow loading from authorized domains
	const currentOrigin = window.location.origin;
	const allowedOrigins = ['https://cheatoid.github.io', 'http://localhost', 'https://localhost', 'file://'];

	// Check if current origin is allowed
	if (!allowedOrigins.some(allowed => currentOrigin.startsWith(allowed))) {
		// Unauthorized origin - trigger immediately
		document.body.innerHTML = '';
		window.location.href = 'about:blank';
		return;
	}

	// Detect abnormal script loading (wireshark/injection)
	function checkScriptLoadingMethod() {
		try {
			// Check if document.currentScript exists
			const currentScript = document.currentScript;
			if (!currentScript) {
				// Script not loaded via normal script tag - might be injected
				return true;
			}

			// Check if script has correct src
			if (!currentScript.src || !currentScript.src.includes('anticheat.js')) {
				// Script src doesn't match expected
				return true;
			}

			// Check if script is in DOM
			const scriptTags = document.querySelectorAll('script[src*="anticheat.js"]');
			if (scriptTags.length !== 1) {
				// No script tag found with anticheat.js
				return true;
			}

			// Check performance timing for abnormal patterns
			if (window.performance && window.performance.getEntriesByName) {
				const entries = window.performance.getEntriesByName('anticheat.js');
				if (entries.length === 0) {
					// No performance entry - might be injected
					return true;
				}
			}

			return false;
		} catch (e) {
			// Error checking - assume abnormal
			return true;
		}
	}

	if (checkScriptLoadingMethod()) {
		triggerAntiCheat('Abnormal script loading detected - possible injection');
		return;
	}

	// Initial stack trace verification to detect side-loading via userscripts
	try {
		throw new Error('stack_check');
	} catch (e) {
		const stack = e.stack || '';
		const stackLines = stack.split('\n').filter(line => line.trim());

		// Check for userscript markers in stack
		if (stack.includes('userscript') || stack.includes('tampermonkey') || stack.includes('greasemonkey') || stack.includes('violentmonkey') || stack.includes('extension') || stack.includes('chrome-extension') || stack.includes('moz-extension')) {
			// Side-loaded via userscript - trigger immediately
			document.body.innerHTML = '';
			window.location.href = 'about:blank';
			return;
		}

		// Check stack depth - too deep might indicate side-loading
		if (stackLines.length > 10) {
			document.body.innerHTML = '';
			window.location.href = 'about:blank';
			return;
		}

		// Check for suspicious stack patterns
		if (stack.includes('eval') && stackLines.length < 3) {
			document.body.innerHTML = '';
			window.location.href = 'about:blank';
			return;
		}
	}

	// Capture original eval immediately to prevent Tampermonkey injection
	const originalEval = eval;
	const originalEvalString = originalEval.toString();

	// Capture original setTimeout to detect tampering
	const originalSetTimeout = setTimeout;
	const originalSetTimeoutString = originalSetTimeout.toString();

	// Secure internal state (not exposed to global scope)
	const internalState = {
		loaded: true,
		secret: Math.random().toString(36).substring(2, 15) + Date.now().toString(36),
		validationKey: Math.random().toString(36).substring(2, 15)
	};

	// Generate unique user hash based on fingerprint
	function generateUserHash() {
		const fingerprintData = navigator.userAgent + navigator.platform + navigator.language + screen.width + screen.height;
		let hash = 0;
		for (let i = 0; i < fingerprintData.length; i++) {
			const char = fingerprintData.charCodeAt(i);
			hash = ((hash << 5) - hash) + char;
			hash = hash & hash;
		}
		return 'banned_' + Math.abs(hash).toString(16) + '_' + Date.now().toString(36);
	}

	const userHash = generateUserHash();

	// Mark user as banned using multiple persistence methods
	function markUserBanned() {
		try {
			// Cookie
			document.cookie = `ac_banned=${userHash}; path=/; max-age=31536000; SameSite=Strict; Secure`;

			// SessionStorage
			sessionStorage.setItem('ac_banned', userHash);

			// LocalStorage
			localStorage.setItem('ac_banned', userHash);

			// IndexedDB
			try {
				const request = indexedDB.open('anticheat_db', 1);
				request.onupgradeneeded = (e) => {
					const db = e.target.result;
					if (!db.objectStoreNames.contains('bans')) {
						db.createObjectStore('bans', {keyPath: 'hash'});
					}
				};
				request.onsuccess = (e) => {
					const db = e.target.result;
					const transaction = db.transaction(['bans'], 'readwrite');
					const store = transaction.objectStore('bans');
					store.put({hash: userHash, timestamp: Date.now()});
				};
			} catch (e) {
			}
		} catch (e) {
		}
	}

	// Check if user is banned
	function checkUserBanned() {
		try {
			let cookieBanned = false;
			let sessionBanned = false;
			let localBanned = false;

			// Check cookie
			const cookies = document.cookie.split(';');
			for (let cookie of cookies) {
				const [name, value] = cookie.trim().split('=');
				if (name === 'ac_banned' && value) {
					cookieBanned = true;
				}
			}

			// Check sessionStorage
			const sessionValue = sessionStorage.getItem('ac_banned');
			if (sessionValue) {
				sessionBanned = true;
			}

			// Check localStorage
			const localValue = localStorage.getItem('ac_banned');
			if (localValue) {
				localBanned = true;
			}

			// Check for inconsistencies - if one is set but others aren't, trigger
			const banCount = (cookieBanned ? 1 : 0) + (sessionBanned ? 1 : 0) + (localBanned ? 1 : 0);
			if (banCount > 0 && banCount < 3) {
				// Inconsistency detected - partial tampering
				triggerAntiCheat('Storage inconsistency detected - partial tampering of ban markers');
				return true;
			}

			// If all three are set, user is banned
			if (banCount === 3) {
				return true;
			}

			// Check IndexedDB
			try {
				const request = indexedDB.open('anticheat_db', 1);
				request.onsuccess = (e) => {
					const db = e.target.result;
					if (db.objectStoreNames.contains('bans')) {
						const transaction = db.transaction(['bans'], 'readonly');
						const store = transaction.objectStore('bans');
						const getRequest = store.get(userHash);
						getRequest.onsuccess = () => {
							if (getRequest.result) {
								triggerAntiCheat('User is banned - IndexedDB record found');
							}
						};
					}
				};
			} catch (e) {
			}

			return false;
		} catch (e) {
			return false;
		}
	}

	// Verify hash integrity (detect tampering)
	function verifyHashIntegrity() {
		try {
			const storedHash = localStorage.getItem('ac_banned') || sessionStorage.getItem('ac_banned');
			if (storedHash && storedHash !== userHash) {
				// Hash was tampered with
				triggerAntiCheat('Hash tampering detected - stored hash does not match');
				return false;
			}
			return true;
		} catch (e) {
			return false;
		}
	}

	// Initial ban check
	if (checkUserBanned()) {
		triggerAntiCheat('User is banned - previous violation detected');
		return;
	}

	// Verify hash integrity
	if (!verifyHashIntegrity()) {
		return;
	}

	// Honey pot cookie - detect tampering
	const honeyPotCookieName = 'ac_session_' + internalState.validationKey;
	const honeyPotCookieValue = btoa(internalState.secret);

	// Set honey pot cookie
	try {
		document.cookie = `${honeyPotCookieName}=${honeyPotCookieValue}; path=/; max-age=86400; SameSite=Strict; Secure`;
	} catch (e) {
	}

	// Check honey pot cookie integrity
	function checkHoneyPotCookie() {
		try {
			const cookies = document.cookie.split(';');
			let found = false;
			let valueMatches = false;

			for (let cookie of cookies) {
				const [name, value] = cookie.trim().split('=');
				if (name === honeyPotCookieName) {
					found = true;
					if (value === honeyPotCookieValue) {
						valueMatches = true;
					}
				}
			}

			if (!found) {
				triggerAntiCheat('Honey pot cookie missing - tampering detected');
				return true;
			}

			if (!valueMatches) {
				triggerAntiCheat('Honey pot cookie modified - tampering detected');
				return true;
			}

			return false;
		} catch (e) {
			return false;
		}
	}

	// Initial honey pot cookie check
	if (checkHoneyPotCookie()) {
		return;
	}

	// Periodic honey pot cookie check with random interval
	const scheduleHoneyPotCheck = () => {
		checkHoneyPotCookie();
		setTimeout(scheduleHoneyPotCheck, Math.floor(Math.random() * 5000) + 3000);
	};
	scheduleHoneyPotCheck();

	// Document integrity check - detect proxy/tampering
	const originalDocumentCookie = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie');
	const originalDocumentGetElementById = document.getElementById;
	const originalDocumentQuerySelector = document.querySelector;

	function checkDocumentIntegrity() {
		try {
			// Check if document is a Proxy
			if (document.toString() !== '[object HTMLDocument]') {
				triggerAntiCheat('Document object appears to be proxied');
				return true;
			}

			// Check if document.cookie descriptor has been modified
			const currentCookieDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie');
			if (currentCookieDescriptor && currentCookieDescriptor.get !== originalDocumentCookie.get) {
				triggerAntiCheat('document.cookie getter has been tampered');
				return true;
			}

			// Check if document.getElementById has been modified
			if (document.getElementById !== originalDocumentGetElementById) {
				triggerAntiCheat('document.getElementById has been tampered');
				return true;
			}

			// Check if document.querySelector has been modified
			if (document.querySelector !== originalDocumentQuerySelector) {
				triggerAntiCheat('document.querySelector has been tampered');
				return true;
			}

			// Check for Proxy in document prototype chain
			const docProto = Object.getPrototypeOf(document);
			if (docProto && docProto.constructor && docProto.constructor.name === 'Proxy') {
				triggerAntiCheat('Document prototype is a Proxy');
				return true;
			}

			return false;
		} catch (e) {
			return false;
		}
	}

	// Initial document integrity check
	if (checkDocumentIntegrity()) {
		return;
	}

	// Periodic document integrity check with random interval
	const scheduleDocumentIntegrityCheck = () => {
		checkDocumentIntegrity();
		setTimeout(scheduleDocumentIntegrityCheck, Math.floor(Math.random() * 4000) + 2000);
	};
	scheduleDocumentIntegrityCheck();

	// Detect if eval has been monkey patched
	function checkEvalPatched() {
		try {
			const currentEvalString = eval.toString();
			if (currentEvalString !== originalEvalString) {
				triggerAntiCheat('eval function has been monkey patched');
				return true;
			}

			// Stack trace verification - call eval and examine stack trace
			try {
				originalEval('throw new Error("eval_stack_test")');
			} catch (e) {
				const stack = e.stack || '';
				// Check if stack contains expected eval markers
				if (!stack.includes('eval') && !stack.includes('Function')) {
					triggerAntiCheat('eval stack trace tampered - missing eval/Function in stack');
					return true;
				}
				// Check for suspicious stack patterns (proxy, wrapper, etc.)
				if (stack.includes('proxy') || stack.includes('wrapper') || stack.includes('intercept')) {
					triggerAntiCheat('eval stack trace tampered - suspicious patterns detected');
					return true;
				}
			}

			return false;
		} catch (e) {
			return false;
		}
	}

	// Check eval integrity periodically with random interval
	const scheduleEvalCheck = () => {
		checkEvalPatched();
		setTimeout(scheduleEvalCheck, Math.floor(Math.random() * 2000) + 1500);
	};
	scheduleEvalCheck();

	// Detect if setTimeout has been monkey patched
	function checkSetTimeoutPatched() {
		try {
			const currentSetTimeoutString = setTimeout.toString();
			if (currentSetTimeoutString !== originalSetTimeoutString) {
				triggerAntiCheat('setTimeout function has been monkey patched');
				return true;
			}
			return false;
		} catch (e) {
			return false;
		}
	}

	// Check setTimeout integrity periodically with random interval
	const scheduleSetTimeoutCheck = () => {
		checkSetTimeoutPatched();
		setTimeout(scheduleSetTimeoutCheck, Math.floor(Math.random() * 3000) + 2000);
	};
	scheduleSetTimeoutCheck();

	// Signal successful load with secure token (not exposed to global scope)
	const secureToken = btoa(internalState.secret + ':' + internalState.validationKey);
	window.dispatchEvent(new CustomEvent('anticheat-loaded', {detail: {secureToken: secureToken}}));

	// Heartbeat validation - verify anticheat is loaded from correct page
	let expectedPage = window.location.pathname;
	let lastHeartbeatTime = Date.now();
	const heartbeatTimeout = 3000;

	// Listen for heartbeat from page
	window.addEventListener('anticheat-heartbeat', function (e) {
		if (e.detail && e.detail.page) {
			lastHeartbeatTime = Date.now();
			// Validate the page matches expected
			if (e.detail.page !== expectedPage) {
				triggerAntiCheat('Heartbeat page mismatch - anticheat loaded from wrong page');
			}
			// Send heartbeat response
			window.dispatchEvent(new CustomEvent('anticheat-heartbeat-response', {
				detail: {valid: true, timestamp: Date.now()}
			}));
		}
	});

	// Check heartbeat periodically
	setInterval(() => {
		if (Date.now() - lastHeartbeatTime > heartbeatTimeout) {
			triggerAntiCheat('Heartbeat timeout - page not communicating with anticheat');
		}
	}, 2000);

	// Honey pot - fake global variable that triggers anti-cheat if modified
	let honeyPotValue = true;
	Object.defineProperty(window, '__anticheat_loaded__', {
		get: function () {
			return honeyPotValue;
		}, set: function (value) {
			triggerAntiCheat('Honey pot __anticheat_loaded__ was modified by user/tampermonkey');
		}, configurable: false, enumerable: true
	});

	// Sneaky devtools detection and redirect
	function triggerAntiCheat(cause) {
		// Mark user as banned
		markUserBanned();

		// Random chance to throw error (triggers infinite loop fallback)
		if (Math.random() < 0.3) {
			setTimeout(() => {
				throw new Error('Anti-cheat triggered');
			}, 0);
		}

		// console.log('=== ANTI-CHEAT TRIGGERED ===');
		// console.log('Cause:', cause);
		// console.log('Timestamp:', new Date().toISOString());
		// console.log('Window size:', window.innerWidth, 'x', window.innerHeight);
		// console.log('Screen size:', screen.width, 'x', screen.height);
		// console.log('User Agent:', navigator.userAgent);

		// Wipe history to prevent back navigation
		try {
			history.pushState(null, '', window.location.href);
			history.pushState(null, '', window.location.href);
			history.pushState(null, '', window.location.href);
			history.pushState(null, '', window.location.href);
			history.pushState(null, '', window.location.href);
			window.addEventListener('popstate', function (e) {
				history.pushState(null, '', window.location.href);
			});
		} catch (e) {
		}

		// Clear the page
		document.body.innerHTML = '';
		document.documentElement.innerHTML = '';

		// Stop all ongoing operations
		const randomDelay = Math.floor(Math.random() * 200) + 40;
		try {
			window.stop();
		} catch (e) {
			// Bad boy - nuke browser with eval to obscure stack trace
			window.setTimeout(() => {
				try {
					originalEval('while(true){}');
				} catch (e2) {
					// Fallback if eval fails
					while (true) {
					}
				}
			}, randomDelay + 50);
		}

		// Aggressive navigation prevention
		window.setTimeout(() => {
			try {
				window.location.href = 'about:blank';
			} catch (e) {
				window.location.replace('about:blank');
			}
		}, randomDelay + 30);

		// Try to close the window/tab
		window.setTimeout(() => {
			try {
				window.close();
			} catch (e) {
				// window.close() may fail if not opened by script
			}
		}, randomDelay);

		// Additional redirect attempts
		window.setTimeout(() => {
			try {
				window.location.href = '';
			} catch (e) {
			}
		}, randomDelay + 100);
	}

	// Global error handler to suppress stack traces and halt browser
	window.onerror = function (message, source, lineno, colno, error) {
		// Fallback - halt browser if error occurs
		try {
			originalEval('while(true){}');
		} catch (e) {
		}
		return true;
	};
	window.onunhandledrejection = function (event) {
		event.preventDefault();
		// Fallback - halt browser if unhandled rejection occurs
		try {
			originalEval('while(true){}');
		} catch (e) {
		}
		return true;
	};

	// Additional error handlers to ensure browser halt
	window.addEventListener('error', function (e) {
		try {
			originalEval('while(true){}');
		} catch (e2) {
		}
	}, true);

	// Deliberately cause infinite loop on any exception
	const originalThrow = Error.prototype.throw;
	Error.prototype.throw = function () {
		try {
			originalEval('while(true){}');
		} catch (e) {
		}
	};

	// Clear console periodically with random interval
	const scheduleConsoleClear = () => {
		try {
			console.clear();
		} catch (e) {
		}
		setTimeout(scheduleConsoleClear, Math.floor(Math.random() * 1000) + 500);
	};
	scheduleConsoleClear();

	// Initialize Web Worker for anti-cheat detection (runs in background to obscure stack traces)
	try {
		const workerCode = `
			let devtoolsOpen = false;
			const secretKey = 'anticheat_heartbeat_secret_' + Math.random().toString(36).substring(2, 15);

			// Use Function constructor as eval alternative (cannot be easily monkey patched in worker)
			const safeEval = (code) => {
				try {
					return Function(code)();
				} catch (e) {
					return null;
				}
			};

			const checkDebugger = () => {
				const start = performance.now();
				try { safeEval('debugger'); } catch (e) {}
				const elapsed = performance.now() - start;
				if (elapsed > 50) {
					postMessage({ type: 'TRIGGER', cause: 'Debugger timing attack (elapsed: ' + elapsed.toFixed(2) + 'ms)' });
				}
				setTimeout(checkDebugger, Math.floor(Math.random() * 1500) + 500);
			};

			const monitorExecution = () => {
				const start = performance.now();
				let dummy = 0;
				for (let i = 0; i < 1000; i++) { dummy += Math.random(); }
				const elapsed = performance.now() - start;
				if (elapsed > 10) {
					postMessage({ type: 'TRIGGER', cause: 'Execution monitoring detected slowdown (' + elapsed.toFixed(2) + 'ms)' });
				}
				setTimeout(monitorExecution, Math.floor(Math.random() * 3000) + 2000);
			};

			const sendHeartbeat = () => {
				const timestamp = Date.now();
				const signature = btoa(secretKey + ':' + timestamp);
				postMessage({ type: 'HEARTBEAT', signature: signature, timestamp: timestamp });
				setTimeout(sendHeartbeat, Math.floor(Math.random() * 400) + 300);
			};

			setTimeout(checkDebugger, Math.floor(Math.random() * 1000));
			setTimeout(monitorExecution, Math.floor(Math.random() * 2000));
			setTimeout(sendHeartbeat, Math.floor(Math.random() * 500));
		`;
		const workerBlob = new Blob([workerCode], {type: 'text/javascript'});
		const workerUrl = URL.createObjectURL(workerBlob);
		const antiCheatWorker = new Worker(workerUrl);

		let lastHeartbeat = Date.now();
		const heartbeatTimeout = Math.floor(Math.random() * 1000) + 1200; // 1.2-2.2 seconds without heartbeat = debugger detected

		const checkHeartbeat = () => {
			if (Date.now() - lastHeartbeat > heartbeatTimeout) {
				triggerAntiCheat('Heartbeat timeout - debugger breakpoint likely active');
			}
			setTimeout(checkHeartbeat, Math.floor(Math.random() * 500) + 300);
		};
		checkHeartbeat();

		antiCheatWorker.onmessage = (e) => {
			if (e.data.type === 'TRIGGER') {
				triggerAntiCheat(e.data.cause);
			} else if (e.data.type === 'HEARTBEAT') {
				lastHeartbeat = Date.now();
			}
		};
	} catch (e) {
		console.log('Worker creation failed:', e);
		// Fallback if worker fails
	}

	// Disable right-click
	document.addEventListener('contextmenu', (e) => {
		e.preventDefault();
		return false;
	});

	// Disable common devtools shortcuts
	document.addEventListener('keydown', (e) => {
		if (e.key === 'F12' || (e.ctrlKey && e.shiftKey && (e.key === 'I' || e.key === 'J' || e.key === 'C' || e.key === 'S')) || (e.ctrlKey && e.key === 'U') || (e.ctrlKey && e.shiftKey && e.key === 'K') || (e.ctrlKey && e.shiftKey && e.key === 'E') || (e.ctrlKey && e.key === 'P') || (e.ctrlKey && e.key === 'S')) {
			e.preventDefault();
			return false;
		}
	});

	// Disable drag and drop
	document.addEventListener('dragstart', (e) => e.preventDefault());
	document.addEventListener('drop', (e) => e.preventDefault());

	// Disable select
	document.addEventListener('selectstart', (e) => e.preventDefault());

	// Disable copy
	document.addEventListener('copy', (e) => e.preventDefault());

	// Disable cut
	document.addEventListener('cut', (e) => e.preventDefault());

	// Disable paste
	document.addEventListener('paste', (e) => e.preventDefault());

})();
