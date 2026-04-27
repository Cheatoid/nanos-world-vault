// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

// Clipboard helper

// Works as UMD (window.ClipboardHelper) and as ESM (export default ClipboardHelper)
(function (global, factory) {
	if (typeof module === 'object' && typeof module.exports === 'object') {
		module.exports = factory();
	} else if (typeof define === 'function' && define.amd) {
		define([], factory);
	} else {
		global.ClipboardHelper = factory();
	}
})(typeof window !== 'undefined' ? window : this, function () {

	// Utility: simple event emitter
	function createEmitter() {
		const listeners = new Map();
		return {
			on(name, fn) {
				if (!listeners.has(name)) listeners.set(name, []);
				listeners.get(name).push(fn);
				return () => this.off(name, fn);
			},
			off(name, fn) {
				if (!listeners.has(name)) return;
				listeners.set(name, listeners.get(name).filter(x => x !== fn));
			},
			emit(name, ...args) {
				if (!listeners.has(name)) return;
				for (const fn of listeners.get(name).slice()) {
					try {
						fn(...args);
					} catch (e) {
						console.error(e);
					}
				}
			}
		};
	}

	// Core helper
	const emitter = createEmitter();
	let listening = false;
	let lastClipboard = null;
	let pasteHandler = null;
	let captureElement = null;

	// Normalize clipboard item to a friendly object
	async function normalizeClipboardData(clipboardData) {
		// clipboardData may be DataTransfer (paste event) or array of ClipboardItem (navigator.clipboard.read)
		const out = {text: null, html: null, items: [], raw: clipboardData};
		try {
			if (!clipboardData) return out;

			// If DataTransfer (paste event)
			if (typeof clipboardData.getData === 'function') {
				out.text = clipboardData.getData('text/plain') || null;
				out.html = clipboardData.getData('text/html') || null;
				// collect files
				if (clipboardData.files && clipboardData.files.length) {
					for (let i = 0; i < clipboardData.files.length; i++) {
						const f = clipboardData.files[i];
						out.items.push({
							kind: 'file',
							type: f.type || 'application/octet-stream',
							blob: f,
							name: f.name || null
						});
					}
				}
				// also check types for other items
				if (clipboardData.types && clipboardData.types.length) {
					for (const t of clipboardData.types) {
						if (t === 'text/plain' || t === 'text/html') continue;
						try {
							const d = clipboardData.getData(t);
							if (d) out.items.push({kind: 'string', type: t, data: d});
						} catch (e) { /* ignore */
						}
					}
				}
				return out;
			}

			// If navigator.clipboard.read() returned ClipboardItem[]
			if (Array.isArray(clipboardData)) {
				for (const item of clipboardData) {
					// ClipboardItem: item.types -> array of MIME types
					for (const type of item.types) {
						try {
							const blob = await item.getType(type);
							if (type.startsWith('text/')) {
								const txt = await blob.text();
								if (type === 'text/html') out.html = out.html || txt;
								else out.text = out.text || txt;
								out.items.push({kind: 'string', type, data: txt});
							} else {
								out.items.push({kind: 'blob', type, blob});
							}
						} catch (e) {
							// ignore individual type failures
						}
					}
				}
				return out;
			}

			// If navigator.clipboard.readText() returned string
			if (typeof clipboardData === 'string') {
				out.text = clipboardData;
				return out;
			}
		} catch (err) {
			console.error('normalizeClipboardData error', err);
		}
		return out;
	}

	// Paste event handler
	function handlePasteEvent(e) {
		try {
			const data = e.clipboardData || window.clipboardData || null;
			normalizeClipboardData(data).then(normalized => {
				normalized.source = 'paste';
				normalized.timestamp = Date.now();
				lastClipboard = normalized;
				emitter.emit('paste', normalized);
			});
		} catch (err) {
			console.error('paste handler error', err);
		}
	}

	// Programmatic read using Async Clipboard API with fallbacks
	async function readClipboard(options = {}) {
		// options: preferText (bool), timeout (ms)
		const preferText = options.preferText !== false; // default true
		const timeout = typeof options.timeout === 'number' ? options.timeout : 5000;

		// 1) Try navigator.clipboard.readText() or read()
		if (navigator.clipboard) {
			try {
				// prefer read() if available and user wants non-text
				if (!preferText && typeof navigator.clipboard.read === 'function') {
					const items = await Promise.race([
						navigator.clipboard.read(),
						new Promise((_, rej) => setTimeout(() => rej(new Error('clipboard.read timeout')), timeout))
					]);
					const normalized = await normalizeClipboardData(items);
					normalized.source = 'navigator.clipboard.read';
					normalized.timestamp = Date.now();
					lastClipboard = normalized;
					emitter.emit('read', normalized);
					return normalized;
				}

				// fallback to readText
				if (typeof navigator.clipboard.readText === 'function') {
					const txt = await Promise.race([
						navigator.clipboard.readText(),
						new Promise((_, rej) => setTimeout(() => rej(new Error('clipboard.readText timeout')), timeout))
					]);
					const normalized = await normalizeClipboardData(txt);
					normalized.source = 'navigator.clipboard.readText';
					normalized.timestamp = Date.now();
					lastClipboard = normalized;
					emitter.emit('read', normalized);
					return normalized;
				}
			} catch (err) {
				// permission denied or not allowed in this context
				// continue to fallbacks
				emitter.emit('error', err);
			}
		}

		// 2) Legacy IE window.clipboardData
		try {
			if (window.clipboardData && typeof window.clipboardData.getData === 'function') {
				const txt = window.clipboardData.getData('Text');
				const normalized = await normalizeClipboardData(txt);
				normalized.source = 'window.clipboardData';
				normalized.timestamp = Date.now();
				lastClipboard = normalized;
				emitter.emit('read', normalized);
				return normalized;
			}
		} catch (err) {
			emitter.emit('error', err);
		}

		// 3) execCommand('paste') fallback using a temporary contenteditable
		// Note: execCommand('paste') usually only works in privileged contexts or with user gesture.
		try {
			// create hidden contenteditable
			if (!captureElement) {
				captureElement = document.createElement('div');
				captureElement.contentEditable = 'true';
				captureElement.style.position = 'fixed';
				captureElement.style.left = '-9999px';
				captureElement.style.width = '1px';
				captureElement.style.height = '1px';
				captureElement.style.overflow = 'hidden';
				captureElement.setAttribute('aria-hidden', 'true');
				document.body.appendChild(captureElement);
			}
			captureElement.innerHTML = '';
			captureElement.focus();

			// execCommand may throw or be blocked
			const ok = document.execCommand && document.execCommand('paste');
			// read the pasted content
			const pasted = captureElement.innerHTML || captureElement.innerText || captureElement.textContent || '';
			const normalized = await normalizeClipboardData(pasted);
			normalized.source = 'execCommand.paste';
			normalized.execCommandResult = !!ok;
			normalized.timestamp = Date.now();
			lastClipboard = normalized;
			emitter.emit('read', normalized);
			return normalized;
		} catch (err) {
			emitter.emit('error', err);
		}

		// 4) Nothing worked
		const empty = {text: null, html: null, items: [], source: 'unavailable', timestamp: Date.now()};
		lastClipboard = empty;
		emitter.emit('read', empty);
		return empty;
	}

	// Public API
	const API = {
		init(options = {}) {
			if (listening) return;
			pasteHandler = handlePasteEvent;
			// capture paste on document to get clipboardData reliably
			document.addEventListener('paste', pasteHandler, true);
			listening = true;
			emitter.emit('init');
			// optional: warm up permission query (non-blocking)
			if (navigator.permissions && navigator.clipboard && navigator.clipboard.readText) {
				try {
					navigator.permissions.query({name: 'clipboard-read'}).then(() => {
					}).catch(() => {
					});
				} catch (e) { /* ignore */
				}
			}
		},

		destroy() {
			if (!listening) return;
			document.removeEventListener('paste', pasteHandler, true);
			pasteHandler = null;
			listening = false;
			if (captureElement && captureElement.parentNode) {
				captureElement.parentNode.removeChild(captureElement);
				captureElement = null;
			}
			emitter.emit('destroy');
		},

		// Returns the last clipboard captured by paste or last successful read
		getLatest() {
			return lastClipboard;
		},

		// Try to read programmatically. Returns normalized clipboard object.
		read(options = {}) {
			return readClipboard(options);
		},

		// Register paste callback: fn(normalizedClipboard)
		onPaste(fn) {
			return emitter.on('paste', fn);
		},

		// Register read callback: fn(normalizedClipboard)
		onRead(fn) {
			return emitter.on('read', fn);
		},

		// Register generic error callback: fn(error)
		onError(fn) {
			return emitter.on('error', fn);
		},

		// Expose emitter for advanced usage
		_emitter: emitter
	};

	// Auto-init so including anywhere will start listening by default.
	// If you prefer manual init, comment out the next line.
	try {
		API.init();
	} catch (e) { /* ignore if DOM not ready */
	}

	// ESM default export compatibility
	if (typeof window !== 'undefined') {
		window.ClipboardHelper = API;
	}

	// Export
	return API;
});
