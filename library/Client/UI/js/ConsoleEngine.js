// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

// Utility
const $ = (sel, ctx = document) => ctx.querySelector(sel);
const $$ = (sel, ctx = document) => [...ctx.querySelectorAll(sel)];
const escHtml = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const now = () => {
	const d = new Date();
	return [d.getHours(), d.getMinutes(), d.getSeconds()]
		.map(v => String(v).padStart(2, '0')).join(':');
};
const getCS = (prop) => getComputedStyle(document.documentElement).getPropertyValue(prop).trim();

// Toast System
const Toast = {
	container: null,
	show(msg, icon = 'fa-check', duration = 2500) {
		if (!this.container) this.container = $('#toastContainer');
		const el = document.createElement('div');
		el.className = 'toast';
		el.innerHTML = `<i class="fas ${icon}" style="color:var(--accent)"></i>${escHtml(msg)}`;
		this.container.appendChild(el);
		setTimeout(() => {
			el.classList.add('removing');
			el.addEventListener('animationend', () => el.remove());
		}, duration);
	}
};

// Theme Manager
const ThemeManager = {
	current: 'amber',
	swatches: {
		amber: '#d4a017',
		arctic: '#0891b2',
		aurora: '#00d4aa',
		bloodmoon: '#ff2020',
		cyberpunk: '#e040fb',
		matrix: '#00ff41',
		midnight: '#4fc1ff'
	},
	set(name) {
		if (!this.swatches[name]) return;
		this.current = name;
		document.body.setAttribute('data-theme', name);
		const swatch = $('#currentSwatch');
		if (swatch) swatch.style.background = this.swatches[name];
		$$('.theme-option').forEach(o => o.classList.toggle('active', o.dataset.theme === name));
		if (typeof Particles !== 'undefined') Particles.updateColor();
	},
	toggleDropdown() {
		const dd = $('#themeDropdown');
		if (!dd) return;
		const isOpen = dd.classList.contains('open');
		dd.classList.toggle('open');
		const btn = $('#themeToggleBtn');
		if (btn) btn.setAttribute('aria-expanded', !isOpen);
	},
	closeDropdown() {
		const dd = $('#themeDropdown');
		if (dd) dd.classList.remove('open');
		const btn = $('#themeToggleBtn');
		if (btn) btn.setAttribute('aria-expanded', 'false');
	}
};

// History Manager
const HistoryManager = {
	entries: [],
	index: -1,
	push(cmd) {
		if (cmd && cmd !== this.entries[this.entries.length - 1]) {
			this.entries.push(cmd);
			if (this.entries.length > 200) this.entries.shift();
		}
		this.index = this.entries.length;
	},
	up() {
		if (this.index > 0) {
			this.index--;
			return this.entries[this.index];
		}
		return null;
	},
	down() {
		if (this.index < this.entries.length - 1) {
			this.index++;
			return this.entries[this.index];
		}
		this.index = this.entries.length;
		return '';
	}
};

// Command Registry
const CommandRegistry = {
	commands: {},
	register(name, desc, fn, opts = {}) {
		this.commands[name] = {desc, fn, alias: opts.alias || [], args: opts.args || ''};
		if (opts.alias) opts.alias.forEach(a => {
			this.commands[a] = this.commands[name];
		});
	},
	get(name) {
		return this.commands[name];
	},
	getAll() {
		return Object.entries(this.commands).filter(([k, v]) => k === Object.keys(this.commands).find(kk => this.commands[kk] === v));
	},
	match(prefix) {
		return this.getAll()
			.filter(([name]) => name.startsWith(prefix.toLowerCase()))
			.map(([name, cmd]) => ({name, desc: cmd.desc, args: cmd.args}))
			.slice(0, 8);
	},
	init() {
		this.register('help', 'Show available commands', () => {
			const lines = this.getAll().map(([n, c]) => `  ${n.padEnd(16)} ${c.desc}`).join('\n');
			return {type: 'info', text: `Available commands:\n${lines}`};
		});
		this.register('clear', 'Clear console output', () => {
			ConsoleEngine.clear();
			return null;
		});
		this.register('cls', 'Clear console (alias)', () => {
			ConsoleEngine.clear();
			return null;
		}, {alias: []});
		this.register('theme', 'Switch theme [name]', (args) => {
			const name = args[0];
			if (!name) return {type: 'info', text: `Themes: ${Object.keys(ThemeManager.swatches).join(', ')}`};
			if (ThemeManager.swatches[name]) {
				ThemeManager.set(name);
				return {type: 'success', text: `Theme changed to "${name}"`};
			}
			return {
				type: 'error',
				text: `Unknown theme "${name}". Available: ${Object.keys(ThemeManager.swatches).join(', ')}`
			};
		});
		this.register('echo', 'Print text to console', (args) => {
			return {type: 'log', text: args.join(' ') || ''};
		});
		this.register('time', 'Show current time', () => {
			return {type: 'info', text: `Current time: ${new Date().toLocaleTimeString()}`};
		});
		this.register('date', 'Show current date', () => {
			return {type: 'info', text: `Current date: ${new Date().toLocaleDateString()}`};
		});
		this.register('version', 'Show version info', () => {
			return {type: 'info', text: 'Console Engine v2.4.0 | Build 20250101'};
		});
		this.register('stats', 'Show message statistics', () => {
			const s = ConsoleEngine.stats;
			return {
				type: 'info',
				text: `Messages - Total: ${s.total} | Log: ${s.log} | Info: ${s.info} | Warn: ${s.warn} | Error: ${s.error} | Debug: ${s.debug} | Success: ${s.success} | Cmd: ${s.cmd}`
			};
		});
		this.register('about', 'About this console', () => {
			const lines = [
				'In-Game Console UI',
				'A modular, themeable, and extensible console system.',
				'Built with vanilla JS, CSS custom properties, and Canvas particles.',
				'Features: themes, search, filters, autocomplete, history, export.',
				'',
				'Press Tab for autocomplete, Up/Down for history.',
			];
			lines.forEach(l => ConsoleEngine.log('info', l));
			return null;
		});
	}
};

// Search / Filter
const FilterManager = {
	activeFilter: 'all',
	searchQuery: '',
	setFilter(type) {
		this.activeFilter = type;
		$$('.filter-chip').forEach(c => c.classList.toggle('active', c.dataset.filter === type));
		this.apply();
	},
	setSearch(q) {
		this.searchQuery = q.toLowerCase().trim();
		this.apply();
	},
	apply() {
		const entries = $$('.msg-entry');
		let visible = 0;
		entries.forEach(el => {
			const type = el.dataset.type;
			const text = el.dataset.text || '';
			const matchFilter = this.activeFilter === 'all' || type === this.activeFilter;
			const matchSearch = !this.searchQuery || text.includes(this.searchQuery);
			const show = matchFilter && matchSearch;
			el.classList.toggle('hidden', !show);
			if (show) {
				visible++;
				if (this.searchQuery) {
					const textEl = el.querySelector('.msg-text');
					if (textEl) {
						const raw = textEl.textContent;
						const regex = new RegExp(`(${this.searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
						textEl.innerHTML = escHtml(raw).replace(regex, '<span class="highlight">$1</span>');
					}
				} else {
					const textEl = el.querySelector('.msg-text');
					if (textEl && textEl.querySelector('.highlight')) {
						textEl.innerHTML = escHtml(textEl.textContent);
					}
				}
			}
		});
		const empty = $('.empty-state');
		if (visible === 0 && entries.length > 0) {
			if (!empty) {
				const e = document.createElement('div');
				e.className = 'empty-state';
				e.innerHTML = '<i class="fas fa-filter"></i><span>No matching messages</span>';
				const output = $('#consoleOutput');
				if (output) output.appendChild(e);
			}
		} else if (empty) {
			empty.remove();
		}
	}
};

// Console Engine
const ConsoleEngine = {
	messages: [],
	stats: {total: 0, log: 0, info: 0, warn: 0, error: 0, debug: 0, success: 0, cmd: 0},
	maxMessages: 2000,
	autoScroll: true,
	isOpen: false,

	log(type, text) {
		const entry = {type, text: String(text), time: now()};
		this.messages.push(entry);
		if (this.messages.length > this.maxMessages) this.messages.shift();
		this.stats.total++;
		this.stats[type] = (this.stats[type] || 0) + 1;
		this.renderEntry(entry);
		this.updateStats();
	},

	renderEntry(entry) {
		const output = $('#consoleOutput');
		if (!output) return;
		const empty = output.querySelector('.empty-state');
		if (empty) empty.remove();

		const div = document.createElement('div');
		div.className = 'msg-entry';
		div.dataset.type = entry.type;
		div.dataset.text = entry.text.toLowerCase();

		const textClass = ['warn', 'error', 'debug', 'success', 'cmd', 'info'].includes(entry.type) ? `${entry.type}-text` : '';

		div.innerHTML = `
<span class="msg-timestamp">${entry.time}</span>
<span class="msg-badge ${entry.type}">${entry.type}</span>
<span class="msg-text ${textClass}">${escHtml(entry.text)}</span>
<span class="msg-actions">
<button class="msg-action-btn" title="Copy" aria-label="Copy message" onclick="ConsoleEngine.copyMessage(this)">
<i class="fas fa-copy"></i>
</button>
</span>
`;
		output.appendChild(div);

		const children = output.children;
		while (children.length > this.maxMessages) children[0].remove();

		if (this.autoScroll) {
			output.scrollTop = output.scrollHeight;
		}
	},

	copyMessage(btn) {
		const entry = btn.closest('.msg-entry');
		const text = entry.querySelector('.msg-text').textContent;
		navigator.clipboard.writeText(text).then(() => {
			Toast.show('Copied to clipboard', 'fa-clipboard-check');
		});
	},

	copyAll() {
		const text = this.messages.map(m => `[${m.time}] [${m.type.toUpperCase()}] ${m.text}`).join('\n');
		navigator.clipboard.writeText(text).then(() => {
			Toast.show(`Copied ${this.messages.length} messages`, 'fa-clipboard-check');
		});
	},

	clear() {
		this.messages = [];
		this.stats = {total: 0, log: 0, info: 0, warn: 0, error: 0, debug: 0, success: 0, cmd: 0};
		const output = $('#consoleOutput');
		if (output) output.innerHTML = '';
		this.updateStats();
		this.showWelcome();
		Toast.show('Console cleared', 'fa-broom');
	},

	updateStats() {
		const statTotal = $('#statTotal');
		const statWarn = $('#statWarn');
		const statError = $('#statError');
		if (statTotal) statTotal.textContent = this.stats.total;
		if (statWarn) statWarn.textContent = this.stats.warn;
		if (statError) statError.textContent = this.stats.error;
		const badge = $('#errorBadge');
		if (badge) {
			if (this.stats.error > 0) {
				badge.textContent = this.stats.error;
				badge.classList.add('visible');
			} else {
				badge.classList.remove('visible');
			}
		}
	},

	execute(input) {
		const trimmed = input.trim();
		if (!trimmed) return;
		HistoryManager.push(trimmed);
		this.log('cmd', trimmed);
		const parts = trimmed.split(/\s+/);
		const cmdName = parts[0].toLowerCase();
		const args = parts.slice(1);
		const cmd = CommandRegistry.get(cmdName);
		if (cmd) {
			try {
				const result = cmd.fn(args);
				if (result) this.log(result.type || 'log', result.text);
			} catch (e) {
				this.log('error', `Command error: ${e.message}`);
			}
		} else {
			this.log('error', `Unknown command: "${cmdName}". Type "help" for available commands.`);
		}
	},

	showWelcome() {
		const output = $('#consoleOutput');
		if (!output) return;
		const banner = document.createElement('div');
		banner.className = 'welcome-banner';
		banner.innerHTML = `
<button class="welcome-close" title="Dismiss">&times;</button>
<h2>Console Engine v0.1</h2>
<p>
Type <kbd>help</kbd> for commands &middot; <kbd>Tab</kbd> to autocomplete &middot; <kbd>&uarr;</kbd><kbd>&darr;</kbd> for history<br>
Use the filter chips above to narrow by type, or search to find specific messages.<br>
Try <kbd>theme cyberpunk</kbd>, or <kbd>time</kbd>.
</p>
`;
		banner.querySelector('.welcome-close').addEventListener('click', () => {
			banner.remove();
		});
		output.appendChild(banner);
	},

	toggle(show) {
		const container = $('#consoleContainer');
		const toggleBtn = $('#toggleBtn');
		const input = $('#consoleInput');
		if (!container || !toggleBtn) return;

		if (show === undefined) {
			show = !this.isOpen;
		}

		this.isOpen = show;
		if (show) {
			container.classList.add('open');
			toggleBtn.style.opacity = '0';
			toggleBtn.style.pointerEvents = 'none';
			setTimeout(() => {
				if (input) input.focus();
			}, 400);
		} else {
			container.classList.remove('open');
			toggleBtn.style.opacity = '1';
			toggleBtn.style.pointerEvents = 'auto';
			Autocomplete.hide();
		}

		// Notify Lua if available
		if (window.ConsoleAPI && window.ConsoleAPI.onToggle) {
			window.ConsoleAPI.onToggle(show);
		}
	}
};

// Autocomplete Provider (for custom autocomplete items)
const AutocompleteProvider = {
	items: [],

	register(name, desc, type = 'command', category = null) {
		this.items.push({name, desc, type, category});
	},

	unregister(name) {
		this.items = this.items.filter(item => item.name !== name);
	},

	clear() {
		this.items = [];
	},

	match(prefix) {
		return this.items
			.filter(item => item.name.toLowerCase().startsWith(prefix.toLowerCase()))
			.map(item => ({name: item.name, desc: item.desc, type: item.type, category: item.category}))
			.slice(0, 8);
	},

	getAll() {
		return this.items;
	}
};

// Autocomplete
const Autocomplete = {
	el: null,
	items: [],
	selected: -1,
	caretPosition: 0, // Track caret position

	show(matches) {
		if (!this.el) this.el = $('#autocomplete');
		this.items = matches;
		this.selected = -1;
		if (matches.length === 0) {
			this.hide();
			return;
		}
		this.el.innerHTML = matches.map((m, i) => `
<div class="autocomplete-item${i === 0 ? ' selected' : ''}" data-index="${i}" role="option">
<span class="cmd-name">${escHtml(m.name)}</span>
<span class="cmd-hint">${escHtml(m.desc)}</span>
</div>
`).join('');
		this.el.classList.add('visible');
		$$('.autocomplete-item', this.el).forEach(item => {
			item.addEventListener('mousedown', (e) => {
				e.preventDefault();
				this.select(parseInt(item.dataset.index));
			});
		});
	},

	hide() {
		if (!this.el) return;
		this.el.classList.remove('visible');
		this.items = [];
		this.selected = -1;
	},

	navigate(dir) {
		if (this.items.length === 0) return;
		this.selected += dir;
		if (this.selected < 0) this.selected = this.items.length - 1;
		if (this.selected >= this.items.length) this.selected = 0;
		$$('.autocomplete-item', this.el).forEach((item, i) => {
			item.classList.toggle('selected', i === this.selected);
		});
	},

	confirmSelection() {
		if (this.selected < 0 || this.selected >= this.items.length) return false;
		this.select(this.selected);
		return true;
	},

	select(index) {
		const item = this.items[index];
		if (!item) return;
		const input = $('#consoleInput');
		if (input) {
			input.value = item.name + ' ';
			this.hide();
			input.focus();
		}
	},

	// Get all autocomplete suggestions (commands + custom items)
	getSuggestions(prefix) {
		const commandMatches = CommandRegistry.match(prefix);
		const customMatches = AutocompleteProvider.match(prefix);

		// Combine and deduplicate
		const all = [...commandMatches, ...customMatches];
		const seen = new Set();
		const unique = [];

		for (const item of all) {
			if (!seen.has(item.name)) {
				seen.add(item.name);
				unique.push(item);
			}
		}

		return unique.slice(0, 8);
	},

	// Update caret position from input
	updateCaretPosition(input) {
		this.caretPosition = input.selectionStart;
	},

	// Get current caret position
	getCaretPosition() {
		return this.caretPosition;
	},

	// Get the word before the caret
	getWordBeforeCaret(input) {
		const text = input.value.substring(0, this.caretPosition);
		const match = text.match(/(\w+)$/);
		return match ? match[1] : '';
	}
};

// Particle Background
const Particles = {
	canvas: null,
	ctx: null,
	particles: [],
	color: '#d4a017',
	running: true,

	init() {
		this.canvas = $('#bgCanvas');
		if (!this.canvas) return;
		this.ctx = this.canvas.getContext('2d', {alpha: true});
		this.resize();
		window.addEventListener('resize', () => this.resize());
		this.createParticles();
		this.animate();
	},

	resize() {
		if (!this.canvas) return;
		this.canvas.width = window.innerWidth;
		this.canvas.height = window.innerHeight;
	},

	updateColor() {
		this.color = getCS('--particle-color') || '#d4a017';
	},

	createParticles() {
		this.particles = [];
		const count = Math.min(Math.floor((window.innerWidth * window.innerHeight) / 12000), 120);
		for (let i = 0; i < count; i++) {
			this.particles.push({
				x: Math.random() * this.canvas.width,
				y: Math.random() * this.canvas.height,
				vx: (Math.random() - 0.5) * 0.3,
				vy: -Math.random() * 0.4 - 0.1,
				size: Math.random() * 2 + 0.5,
				opacity: Math.random() * 0.5 + 0.1,
				life: Math.random(),
			});
		}
	},

	animate() {
		if (!this.running || !this.ctx) return;
		this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
		this.color = getCS('--particle-color') || '#d4a017';

		for (const p of this.particles) {
			p.x += p.vx;
			p.y += p.vy;
			p.life += 0.002;

			if (p.y < -10 || p.life > 1) {
				p.x = Math.random() * this.canvas.width;
				p.y = this.canvas.height + 10;
				p.life = 0;
				p.opacity = Math.random() * 0.5 + 0.1;
			}

			const alpha = p.opacity * Math.sin(p.life * Math.PI);
			this.ctx.beginPath();
			this.ctx.arc(p.x, p.y, Math.max(0.1, p.size), 0, Math.PI * 2);
			this.ctx.fillStyle = this.color;
			this.ctx.globalAlpha = Math.max(0, alpha);
			this.ctx.fill();
		}
		this.ctx.globalAlpha = 1;
		requestAnimationFrame(() => this.animate());
	}
};

// Public API for Lua
window.ConsoleAPI = {
	// Logging
	log(type, text) {
		ConsoleEngine.log(type, text);
	},
	info(text) {
		ConsoleEngine.log('info', text);
	},
	warn(text) {
		ConsoleEngine.log('warn', text);
	},
	error(text) {
		ConsoleEngine.log('error', text);
	},
	debug(text) {
		ConsoleEngine.log('debug', text);
	},
	success(text) {
		ConsoleEngine.log('success', text);
	},

	// Console control
	clear() {
		ConsoleEngine.clear();
	},
	toggle(show) {
		ConsoleEngine.toggle(show);
	},
	setTheme(theme) {
		ThemeManager.set(theme);
	},

	// Command registration
	registerCommand(name, desc, handler) {
		CommandRegistry.register(name, desc, (args) => {
			// Call Lua handler via event if available
			if (window.ConsoleAPI.onCommand) {
				const result = window.ConsoleAPI.onCommand(name, args);
				if (result) return result;
			}
			// Fallback to JS handler
			if (handler) return handler(args);
			return null;
		});
	},

	// Callbacks (to be set by Lua)
	onCommand: null,
	onToggle: null
};

// Nanos-world WebUI Event Listeners
if (typeof WebUI !== 'undefined') {
	// Logging events
	WebUI.Subscribe('log', (type, text) => ConsoleEngine.log(type, text));
	WebUI.Subscribe('info', (text) => ConsoleEngine.log('info', text));
	WebUI.Subscribe('warn', (text) => ConsoleEngine.log('warn', text));
	WebUI.Subscribe('error', (text) => ConsoleEngine.log('error', text));
	WebUI.Subscribe('debug', (text) => ConsoleEngine.log('debug', text));
	WebUI.Subscribe('success', (text) => ConsoleEngine.log('success', text));

	// Control events
	WebUI.Subscribe('clear', () => ConsoleEngine.clear());
	WebUI.Subscribe('toggle', (show) => ConsoleEngine.toggle(show));
	WebUI.Subscribe('setTheme', (theme) => ThemeManager.set(theme));

	// Command registration
	WebUI.Subscribe('registerCommand', (name, desc) => {
		CommandRegistry.register(name, desc, (args) => {
			// Call back to Lua for execution
			if (typeof WebUI !== 'undefined') {
				WebUI.CallEvent('onCommand', name, args);
			}
			return null;
		});
	});

	// Autocomplete provider events
	WebUI.Subscribe('registerAutocomplete', (name, desc, type, category) => {
		AutocompleteProvider.register(name, desc, type, category);
	});

	WebUI.Subscribe('unregisterAutocomplete', (name) => {
		AutocompleteProvider.unregister(name);
	});

	WebUI.Subscribe('clearAutocomplete', () => {
		AutocompleteProvider.clear();
	});

	// Caret position events
	WebUI.Subscribe('getCaretPosition', () => {
		const input = $('#consoleInput');
		if (input) {
			Autocomplete.updateCaretPosition(input);
			WebUI.CallEvent('caretPosition', Autocomplete.getCaretPosition(), input.value, Autocomplete.getWordBeforeCaret(input));
		}
	});
}

// Initialization
document.addEventListener('DOMContentLoaded', () => {
	CommandRegistry.init();
	Particles.init();
	ConsoleEngine.showWelcome();

	const container = $('#consoleContainer');
	const toggleBtn = $('#toggleBtn');
	const input = $('#consoleInput');

	// Toggle console
	toggleBtn.addEventListener('click', () => ConsoleEngine.toggle(true));
	const closeBtn = $('#closeBtn');
	if (closeBtn) closeBtn.addEventListener('click', () => ConsoleEngine.toggle(false));

	// Keyboard shortcuts
	document.addEventListener('keydown', (e) => {
		if (e.key === '`' || e.key === '~') {
			if (document.activeElement === input) {
				e.preventDefault();
				ConsoleEngine.toggle(false);
			} else {
				e.preventDefault();
				ConsoleEngine.toggle();
			}
		}
		if (e.key === 'Escape' && ConsoleEngine.isOpen) {
			ConsoleEngine.toggle(false);
		}
	});

	// Maximize
	let isMaximized = false;
	const maximizeBtn = $('#maximizeBtn');
	if (maximizeBtn) {
		maximizeBtn.addEventListener('click', () => {
			isMaximized = !isMaximized;
			container.classList.toggle('maximized', isMaximized);
			maximizeBtn.innerHTML = isMaximized
				? '<i class="fas fa-compress"></i>'
				: '<i class="fas fa-expand"></i>';
		});
	}

	// Copy all
	const copyAllBtn = $('#copyAllBtn');
	if (copyAllBtn) copyAllBtn.addEventListener('click', () => ConsoleEngine.copyAll());

	// Filter chips
	$$('.filter-chip').forEach(chip => {
		chip.addEventListener('click', () => FilterManager.setFilter(chip.dataset.filter));
	});

	// Search
	let searchTimeout;
	const searchInput = $('#searchInput');
	if (searchInput) {
		searchInput.addEventListener('input', (e) => {
			clearTimeout(searchTimeout);
			searchTimeout = setTimeout(() => FilterManager.setSearch(e.target.value), 150);
		});
	}

	// Auto-scroll toggle
	const autoScrollBtn = $('#autoScrollBtn');
	if (autoScrollBtn) {
		autoScrollBtn.addEventListener('click', () => {
			ConsoleEngine.autoScroll = !ConsoleEngine.autoScroll;
			autoScrollBtn.classList.toggle('active', ConsoleEngine.autoScroll);
			if (ConsoleEngine.autoScroll) {
				const output = $('#consoleOutput');
				if (output) output.scrollTop = output.scrollHeight;
			}
		});
	}

	// Theme dropdown
	const themeToggleBtn = $('#themeToggleBtn');
	if (themeToggleBtn) {
		themeToggleBtn.addEventListener('click', (e) => {
			e.stopPropagation();
			ThemeManager.toggleDropdown();
		});
	}
	$$('.theme-option').forEach(opt => {
		opt.addEventListener('click', () => {
			ThemeManager.set(opt.dataset.theme);
			ThemeManager.closeDropdown();
			Toast.show(`Theme: ${opt.textContent.trim()}`, 'fa-palette');
		});
	});
	document.addEventListener('click', () => ThemeManager.closeDropdown());

	// Command input
	if (input) {
		// Track caret position on click and keyup
		input.addEventListener('click', () => {
			Autocomplete.updateCaretPosition(input);
		});

		input.addEventListener('keyup', () => {
			Autocomplete.updateCaretPosition(input);
		});

		input.addEventListener('select', () => {
			Autocomplete.updateCaretPosition(input);
		});

		input.addEventListener('keydown', (e) => {
			if (e.key === 'Enter') {
				if (Autocomplete.confirmSelection()) return;
				const val = input.value;
				input.value = '';
				Autocomplete.hide();
				ConsoleEngine.execute(val);
			} else if (e.key === 'Tab') {
				e.preventDefault();
				if (!Autocomplete.confirmSelection()) {
					const val = input.value.trim();
					if (val) {
						const matches = Autocomplete.getSuggestions(val);
						if (matches.length === 1) {
							input.value = matches[0].name + ' ';
							Autocomplete.hide();
						} else if (matches.length > 1) {
							Autocomplete.show(matches);
						}
					}
				}
			} else if (e.key === 'ArrowUp') {
				e.preventDefault();
				if (Autocomplete.items.length > 0) {
					Autocomplete.navigate(-1);
				} else {
					const prev = HistoryManager.up();
					if (prev !== null) input.value = prev;
				}
			} else if (e.key === 'ArrowDown') {
				e.preventDefault();
				if (Autocomplete.items.length > 0) {
					Autocomplete.navigate(1);
				} else {
					const next = HistoryManager.down();
					if (next !== null) input.value = next;
				}
			} else if (e.key === 'Escape') {
				Autocomplete.hide();
			}
		});

		input.addEventListener('input', () => {
			Autocomplete.updateCaretPosition(input);
			const val = input.value.trim();
			if (val.length >= 1) {
				const matches = Autocomplete.getSuggestions(val);
				if (matches.length > 0 && (matches.length > 1 || matches[0].name !== val)) {
					Autocomplete.show(matches);
				} else {
					Autocomplete.hide();
				}
			} else {
				Autocomplete.hide();
			}
		});
	}

	// Manual scroll detection
	const consoleOutput = $('#consoleOutput');
	if (consoleOutput) {
		consoleOutput.addEventListener('scroll', () => {
			const atBottom = consoleOutput.scrollHeight - consoleOutput.scrollTop - consoleOutput.clientHeight < 30;
			if (!atBottom && ConsoleEngine.autoScroll) {
				ConsoleEngine.autoScroll = false;
				if (autoScrollBtn) autoScrollBtn.classList.remove('active');
			}
		});
	}
});
