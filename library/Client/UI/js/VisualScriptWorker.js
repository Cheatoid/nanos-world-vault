// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

// Global state for step execution
let stepState = {
	nodes: [],
	edges: [],
	nodeMap: {},
	inDegree: {},
	adj: {},
	sorted: [],
	nodeOutputs: {},
	currentStepIndex: 0,
	isStepMode: true,
	// Control flow state management
	controlFlowState: new Map() // nodeId -> {iteration, index, done, etc}
};

self.onmessage = function (e) {
	const { type, nodes, edges, stepIndex, affectedNodes } = e.data;

	if (type === 'run') {
		// Normal execution mode
		const results = executeGraph(nodes, edges);
		self.postMessage(results);
	} else if (type === 'runSelective') {
		// Selective execution mode for live updates
		const results = executeGraphSelective(nodes, edges, affectedNodes);
		self.postMessage(results);
	} else if (type === 'initStep') {
		// Initialize step execution mode
		initializeStepMode(nodes, edges);
		self.postMessage({ type: 'stepInitialized', executionQueue: stepState.sorted });
	} else if (type === 'step') {
		// Execute single step
		const stepResult = executeStep(stepIndex);
		self.postMessage(stepResult);
	}
};

function executeGraph(nodes, edges) {
	// Use the step engine but run every step automatically (no pausing)
	initializeStepMode(nodes, edges);

	// Safety guard against infinite loops (e.g. while-true)
	let safety = 0;
	const MAX_STEPS = 10000;

	while (safety < MAX_STEPS) {
		const result = executeStep(stepState.currentStepIndex++);
		if (result.isComplete) break;
		safety++;
	}

	if (safety >= MAX_STEPS) {
		console.warn('Execution halted: exceeded maximum step limit (possible infinite loop)');
	}

	// Return final node outputs in the same format the UI expects
	const results = {};
	for (const nodeId in stepState.nodeOutputs) {
		results[nodeId] = stepState.nodeOutputs[nodeId];
	}
	return results;
}

function executeGraphSelective(nodes, edges, affectedNodes) {
	const results = {};

	// If no affected nodes specified, return empty results
	if (!affectedNodes || affectedNodes.length === 0) {
		return results;
	}

	// Build graph structure
	const inDegree = {};
	const adj = {};
	const nodeMap = {};
	nodes.forEach(n => {
		nodeMap[n.id] = n;
		inDegree[n.id] = 0;
		adj[n.id] = [];
	});
	edges.forEach(e => {
		adj[e.fromNode] = adj[e.fromNode] || [];
		adj[e.fromNode].push(e);
		inDegree[e.toNode] = (inDegree[e.toNode] || 0) + 1;
	});

	// Find all nodes that need to be executed (affected nodes + their dependencies + downstream nodes)
	const nodesToExecute = new Set(affectedNodes);
	const queue = [...affectedNodes];

	// Find all dependencies of affected nodes
	while (queue.length > 0) {
		const nodeId = queue.shift();
		const incomingEdges = edges.filter(e => e.toNode === nodeId);

		for (const edge of incomingEdges) {
			if (!nodesToExecute.has(edge.fromNode)) {
				nodesToExecute.add(edge.fromNode);
				queue.push(edge.fromNode);
			}
		}
	}

	// Find all downstream nodes that depend on affected nodes
	const downstreamQueue = [...affectedNodes];
	while (downstreamQueue.length > 0) {
		const nodeId = downstreamQueue.shift();
		const outgoingEdges = edges.filter(e => e.fromNode === nodeId);

		for (const edge of outgoingEdges) {
			if (!nodesToExecute.has(edge.toNode)) {
				nodesToExecute.add(edge.toNode);
				downstreamQueue.push(edge.toNode);
			}
		}
	}

	// Ensure all dependencies for ALL nodes in nodesToExecute are included
	// (downstream nodes may have dependencies that were not in the original affected set)
	const depQueue = Array.from(nodesToExecute);
	while (depQueue.length > 0) {
		const nodeId = depQueue.shift();
		const incomingEdges = edges.filter(e => e.toNode === nodeId);
		for (const edge of incomingEdges) {
			if (!nodesToExecute.has(edge.fromNode)) {
				nodesToExecute.add(edge.fromNode);
				depQueue.push(edge.fromNode);
			}
		}
	}

	// Topological sort only the nodes we need to execute
	const queue2 = Array.from(nodesToExecute).filter(nId => inDegree[nId] === 0).map(nId => nId);
	const sorted = [];

	while (queue2.length > 0) {
		const curr = queue2.shift();
		sorted.push(curr);
		(adj[curr] || []).forEach(edge => {
			if (nodesToExecute.has(edge.toNode)) {
				inDegree[edge.toNode]--;
				if (inDegree[edge.toNode] === 0) queue2.push(edge.toNode);
			}
		});
	}

	// Evaluate only the nodes we need to execute
	const nodeOutputs = {};
	sorted.forEach(nodeId => {
		const node = nodeMap[nodeId];
		if (!node) return;
		const inputs = { ...node.data };

		console.log(`Selective execution: executing node ${nodeId} (${node.type}) with inputs:`, inputs);

		// Fill inputs from connected outputs
		edges.forEach(edge => {
			if (edge.toNode === nodeId) {
				const fromOut = nodeOutputs[edge.fromNode];
				if (fromOut && fromOut[edge.fromPort] !== undefined) {
					inputs[edge.toPort] = fromOut[edge.fromPort];
				}
			}
		});

		// Calculate
		const outputs = executeNode(node.type, inputs);
		console.log(`Selective execution: node ${nodeId} output:`, outputs);
		nodeOutputs[nodeId] = outputs || {};
		results[nodeId] = outputs || {};
	});

	return results;
}

function initializeStepMode(nodes, edges) {
	stepState.nodes = nodes;
	stepState.edges = edges;
	stepState.nodeMap = {};
	stepState.inDegree = {};
	stepState.adj = {};
	stepState.nodeOutputs = {};
	stepState.currentStepIndex = 0;
	stepState.isStepMode = true;
	stepState.controlFlowState.clear();
	stepState.executionQueue = [];
	stepState.currentExecutionNode = null;
	stepState.executionOrder = 0;

	// Explicitly clear any accumulated print data
	stepState.nodeOutputs = {};
	stepState.executionOrder = 0;

	// Build graph structure for step execution
	nodes.forEach(n => {
		stepState.nodeMap[n.id] = n;
		stepState.inDegree[n.id] = 0;
		stepState.adj[n.id] = [];
	});

	edges.forEach(e => {
		stepState.adj[e.fromNode] = stepState.adj[e.fromNode] || [];
		stepState.adj[e.fromNode].push(e);
		stepState.inDegree[e.toNode] = (stepState.inDegree[e.toNode] || 0) + 1;
	});

	// Find entry points (nodes with no dependencies)
	const entryNodes = nodes.filter(n => stepState.inDegree[n.id] === 0).map(n => n.id);
	stepState.executionQueue = [...entryNodes];

	// Initialize control flow state for for-loop nodes
	nodes.forEach(n => {
		if (n.type === 'control-flow/for-loop') {
			stepState.controlFlowState.set(n.id, {
				currentIndex: Number(n.data.start) || 0,
				start: Number(n.data.start) || 0,
				end: Number(n.data.end) || 10,
				step: Number(n.data.step) || 1,
				done: false,
				isLooping: false,
				iterationCount: 0
			});
		}
	});
}

function executeStep(stepIndex) {
	if (!stepState.isStepMode) {
		return {
			type: 'stepResult',
			nodeId: null,
			results: {},
			isComplete: true,
			executionQueue: []
		};
	}

	// Get the next node to execute
	let nodeId = null;
	if (stepState.currentExecutionNode) {
		nodeId = stepState.currentExecutionNode;
	} else if (stepState.executionQueue.length > 0) {
		nodeId = stepState.executionQueue.shift();
	} else {
		return {
			type: 'stepResult',
			nodeId: null,
			results: {},
			isComplete: true,
			executionQueue: []
		};
	}

	const node = stepState.nodeMap[nodeId];
	if (!node) {
		return {
			type: 'stepResult',
			nodeId: null,
			results: {},
			isComplete: true,
			executionQueue: []
		};
	}

	const inputs = { ...node.data };

	// Fill inputs from connected outputs (using step state)
	stepState.edges.forEach(edge => {
		if (edge.toNode === nodeId) {
			const fromOut = stepState.nodeOutputs[edge.fromNode];
			if (fromOut && fromOut[edge.fromPort] !== undefined) {
				inputs[edge.toPort] = fromOut[edge.fromPort];
			}
		}
	});

	// ========== EXECUTE NODE ==========
	let outputs; // <-- prevents implicit global

	if (node.type === 'control-flow/for-loop') {
		const loopState = stepState.controlFlowState.get(nodeId);
		if (!loopState) {
			// Emergency fallback - use actual node data
			const emergencyState = {
				currentIndex: Number(node.data.start) || 0,
				start: Number(node.data.start) || 0,
				end: Number(node.data.end) || 10,
				step: Number(node.data.step) || 1,
				done: false,
				isLooping: false,
				iterationCount: 0
			};
			stepState.controlFlowState.set(nodeId, emergencyState);
			const startIndex = Number(node.data.start) || 0;
			const endIndex = Number(node.data.end) || 10;
			outputs = { index: startIndex, done: false, _display: `${startIndex} / ${endIndex}` };
		} else {
			// Refresh parameters from inputs or node data
			loopState.start = inputs.start !== undefined ? Number(inputs.start) : (node.data.start !== undefined ? Number(node.data.start) : 0);
			loopState.end = inputs.end !== undefined ? Number(inputs.end) : (node.data.end !== undefined ? Number(node.data.end) : 10);
			loopState.step = inputs.step !== undefined ? Number(inputs.step) : (node.data.step !== undefined ? Number(node.data.step) : 1);

			if (isNaN(loopState.start)) loopState.start = 0;
			if (isNaN(loopState.end)) loopState.end = 10;
			if (isNaN(loopState.step)) loopState.step = 1;

			// First visit: initialize
			if (!loopState.isLooping) {
				loopState.currentIndex = loopState.start;
				loopState.isLooping = true;
				loopState.iterationCount = 0;
			}

			const currentIterationValue = loopState.currentIndex;
			const isFinalIteration = loopState.step > 0
				? currentIterationValue >= loopState.end
				: currentIterationValue <= loopState.end;

			outputs = {
				index: currentIterationValue,
				done: isFinalIteration,
				_display: `${currentIterationValue} / ${loopState.end}`
			};

			// Advance for the *next* iteration
			loopState.currentIndex += loopState.step;
			const done = loopState.step > 0
				? loopState.currentIndex > loopState.end
				: loopState.currentIndex < loopState.end;

			// Queue dependents so they run with the current value
			(stepState.adj[nodeId] || []).forEach(edge => {
				stepState.executionQueue.push(edge.toNode);
			});

			stepState.currentExecutionNode = null;

			if (!done) {
				// Re-queue loop for next iteration
				stepState.executionQueue.push(nodeId);
				loopState.iterationCount++;
			} else {
				loopState.isLooping = false;
			}
		}
	} else {
		// Regular node execution
		outputs = executeNode(node.type, inputs);

		// Queue dependent nodes
		(stepState.adj[nodeId] || []).forEach(edge => {
			stepState.executionQueue.push(edge.toNode);
		});
	}

	// Special handling for print nodes to accumulate all outputs in order
	if (node.type === 'output/print') {
		if (!stepState.nodeOutputs[nodeId]) {
			stepState.nodeOutputs[nodeId] = { _print: [] };
		}
		if (outputs && outputs._print !== undefined) {
			// Add with execution order to maintain temporal sequence
			stepState.nodeOutputs[nodeId]._print.push({
				value: outputs._print,
				order: stepState.executionOrder || 0
			});
			stepState.executionOrder = (stepState.executionOrder || 0) + 1;
		}
	} else {
		stepState.nodeOutputs[nodeId] = outputs || {};
	}

	const isComplete = stepState.executionQueue.length === 0 && !stepState.currentExecutionNode;

	return {
		type: 'stepResult',
		nodeId: nodeId,
		results: outputs || {},
		isComplete: isComplete,
		executionQueue: stepState.executionQueue,
		currentExecutionNode: stepState.currentExecutionNode
	};
}

function executeNode(type, inputs) {
	switch (type) {
		// ==================== VALUE NODES ====================
		case 'value/number':
			return { out: Number(inputs.value) || 0 };
		case 'value/string':
			return { out: String(inputs.value) };
		case 'value/boolean':
			return { out: !!inputs.value };

		// ==================== MATH OPERATIONS ====================
		case 'math/add':
			return { sum: (Number(inputs.a) || 0) + (Number(inputs.b) || 0) };
		case 'math/subtract':
			return { diff: (Number(inputs.a) || 0) - (Number(inputs.b) || 0) };
		case 'math/multiply':
			return { product: (Number(inputs.a) || 0) * (Number(inputs.b) || 0) };
		case 'math/divide': {
			const b = Number(inputs.b) || 1;
			return { quotient: b !== 0 ? (Number(inputs.a) || 0) / b : 0 };
		}
		case 'math/modulo': {
			const b = Number(inputs.b) || 1;
			return { remainder: b !== 0 ? (Number(inputs.a) || 0) % b : 0 };
		}
		case 'math/power':
			return { result: Math.pow(Number(inputs.base) || 0, Number(inputs.exp) || 0) };
		case 'math/sqrt':
			return { result: Math.sqrt(Math.max(0, Number(inputs.value) || 0)) };
		case 'math/min':
			return { result: Math.min(Number(inputs.a) || 0, Number(inputs.b) || 0) };
		case 'math/max':
			return { result: Math.max(Number(inputs.a) || 0, Number(inputs.b) || 0) };

		// ==================== LOGIC OPERATIONS ====================
		case 'logic/and':
			return { out: !!inputs.a && !!inputs.b };
		case 'logic/or':
			return { out: !!inputs.a || !!inputs.b };
		case 'logic/not':
			return { out: !inputs.input };
		case 'logic/xor':
			return { out: (!!inputs.a !== !!inputs.b) };

		// ==================== COMPARISON OPERATIONS ====================
		case 'logic/equals':
			return { result: inputs.a == inputs.b };
		case 'logic/not-equals':
			return { result: inputs.a != inputs.b };
		case 'logic/less':
			return { result: (Number(inputs.a) || 0) < (Number(inputs.b) || 0) };
		case 'logic/less-equals':
			return { result: (Number(inputs.a) || 0) <= (Number(inputs.b) || 0) };
		case 'logic/greater':
			return { result: (Number(inputs.a) || 0) > (Number(inputs.b) || 0) };
		case 'logic/greater-equals':
			return { result: (Number(inputs.a) || 0) >= (Number(inputs.b) || 0) };

		// ==================== CONTROL FLOW ====================
		case 'control-flow/if': {
			// Convert string boolean inputs to actual boolean
			let condition = inputs.condition;
			if (typeof condition === 'string') {
				condition = condition.toLowerCase() === 'true';
			}
			return { result: condition ? inputs['true'] : inputs['false'] };
		}
		case 'control-flow/switch': {
			const index = Math.max(1, Math.min(4, Math.floor(Number(inputs.input) || 1)));
			return { result: inputs['case' + index] || 0 };
		}
		case 'control-flow/for-loop': {
			const start = Number(inputs.start) || 0;
			const end = Number(inputs.end) || 10;
			const step = Number(inputs.step) || 1;
			const index = start;
			const done = step > 0 ? index >= end : index <= end;
			console.log('For Loop executeNode:', { start, end, step, index, done });
			return { index, done, _display: `${index} / ${end}` };
		}
		case 'control-flow/while-loop':
			return { value: inputs.value, continue: !!inputs.condition };
		case 'logic/merge':
			return { result: inputs.input1 || inputs.input2 || inputs.input3 || inputs.input4 };
		case 'control/counter': {
			const increment = Number(inputs.increment) || 1;
			const reset = !!inputs.reset;
			const count = reset ? 0 : (inputs._count || 0) + increment;
			return { count, _count: count, _display: String(count) };
		}
		case 'control/range': {
			const min = Number(inputs.min) || 0;
			const max = Number(inputs.max) || 100;
			const value = Number(inputs.value) || 0;
			const clamped = Math.max(min, Math.min(max, value));
			const range = max - min;
			const normalized = range !== 0 ? (clamped - min) / range : 0;
			return { clamped, normalized };
		}
		case 'control/delay':
			return { value: inputs.value, _display: `${inputs.ms}ms delay` };
		case 'control/variable-gate': {
			const reset = !!inputs.reset;
			const type = inputs.type || 'any';
			let storedValue = reset ? inputs.set : (inputs._stored !== undefined ? inputs._stored : inputs.set);

			// Type conversion based on selected type
			switch (type) {
				case 'number':
					storedValue = Number(storedValue) || 0;
					break;
				case 'string':
					storedValue = String(storedValue);
					break;
				case 'boolean':
					storedValue = !!storedValue;
					break;
				default:
					// 'any' - pass through as-is
					break;
			}

			return { value: storedValue, _stored: storedValue, _display: `${type}: ${String(storedValue)}` };
		}

		// ==================== CONTROL FLOW ====================
		case 'control/group':
			return {
				_display: inputs.collapsed ? '▶ Group' : '▼ Group',
				collapsed: !!inputs.collapsed
			};

		// ==================== OUTPUT NODES ====================
		case 'output/display':
			return {
				_display: inputs.value !== undefined ? String(inputs.value) : '—',
				out: inputs.value,
				_print: inputs.value !== undefined ? String(inputs.value) : '—'  // duplicate _print here but we need it only for print type; leaving harmless
			};

		// ==================== PRINT NODE ====================
		case 'output/print':
			return {
				_print: inputs.value !== undefined ? String(inputs.value) : '—'
			};

		// ==================== UTILITY NODES ====================
		case 'color/mix': {
			try {
				const hex = (s) => parseInt(s.replace('#', ''), 16);
				const r1 = (hex(inputs.c1) >> 16) & 255, g1 = (hex(inputs.c1) >> 8) & 255, b1 = hex(inputs.c1) & 255;
				const r2 = (hex(inputs.c2) >> 16) & 255, g2 = (hex(inputs.c2) >> 8) & 255, b2 = hex(inputs.c2) & 255;
				const t = Math.max(0, Math.min(1, Number(inputs.t) || 0));
				const mix = (a, b) => Math.round(a + (b - a) * t);
				const rh = mix(r1, r2).toString(16).padStart(2, '0');
				const gh = mix(g1, g2).toString(16).padStart(2, '0');
				const bh = mix(b1, b2).toString(16).padStart(2, '0');
				return { out: '#' + rh + gh + bh };
			} catch (e) {
				return { out: '#888888' };
			}
		}

		// ==================== DEFAULT ====================
		default:
			return {};
	}
}
