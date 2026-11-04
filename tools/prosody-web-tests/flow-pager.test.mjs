import test from 'node:test';
import assert from 'node:assert/strict';
import { createFlowPager } from '../../apps/client/web/prosody/flow-pager.js';

class Element {
  constructor(tagName = 'div', parentElement = null) {
    this.tagName = tagName;
    this.parentElement = parentElement;
    this.attributes = new Map();
    this.listeners = new Map();
    this.dataset = {};
    this.hidden = false;
    this.inert = false;
    this.disabled = false;
    this.textContent = '';
  }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  removeAttribute(name) { this.attributes.delete(name); }
  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type).add(listener);
  }
  removeEventListener(type, listener) { this.listeners.get(type)?.delete(listener); }
  dispatch(type, values = {}) {
    const event = { target: this, cancelable: true, defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; },
      stopPropagation() { this.propagationStopped = true; },
      stopImmediatePropagation() { this.immediatePropagationStopped = true; }, ...values };
    for (const listener of [...(this.listeners.get(type) || [])]) listener(event);
    return event;
  }
  focus() { this.focused = true; }
  get listenerCount() { return [...this.listeners.values()].reduce((sum, set) => sum + set.size, 0); }
}

function setup({ guide = true, result = false, busy = false } = {}) {
  const pages = Array.from({ length: 3 }, () => new Element());
  const stepButtons = pages.map(() => new Element('button'));
  const previousButton = new Element('button'), nextButton = new Element('button');
  const positionLabel = new Element(), gestureTarget = new Element();
  const state = { guide, result, busy }, changes = [];
  let pager;
  pager = createFlowPager({ pages, stepButtons, previousButton, nextButton, positionLabel, gestureTarget,
    canEnter: index => index === 0 || (index === 1 ? state.guide : state.result),
    canMove: () => !state.busy,
    onChanged: index => { changes.push(index); pager.refresh(); },
  });
  const swipe = (dx, dy = 0, { target = gestureTarget, move = null, endTarget = target, pointerId = 1 } = {}) => {
    gestureTarget.dispatch('pointerdown', { target, pointerId, isPrimary: true, button: 0, clientX: 150, clientY: 150 });
    if (move) gestureTarget.dispatch('pointermove', { target, pointerId, clientX: 150 + move[0], clientY: 150 + move[1] });
    return gestureTarget.dispatch('pointerup', { target: endTarget, pointerId, clientX: 150 + dx, clientY: 150 + dy });
  };
  return { pager, pages, stepButtons, previousButton, nextButton, positionLabel, gestureTarget, state, changes, swipe };
}

test('initial page, hidden/inert panes and forward/back controls reflect navigation guards', () => {
  const f = setup({ guide: false });
  assert.equal(f.pager.index, 0);
  assert.equal(f.positionLabel.textContent, '1 / 3');
  assert.deepEqual(f.pages.map(p => [p.hidden, p.inert]), [[false, false], [true, true], [true, true]]);
  assert.equal(f.stepButtons[0].getAttribute('aria-current'), 'step');
  assert.equal(f.stepButtons[1].getAttribute('aria-current'), null);
  assert.equal(f.stepButtons[1].getAttribute('aria-disabled'), 'true');
  assert.equal(f.stepButtons[1].disabled, true);
  assert.equal(f.previousButton.disabled, true);
  assert.equal(f.nextButton.disabled, true);
  assert.equal(f.pager.goTo(1), false);
  assert.equal(f.pager.goTo(2), false);
  f.state.guide = true;
  f.pager.refresh();
  assert.equal(f.nextButton.disabled, false);
  assert.equal(f.nextButton.textContent, '녹음하기 →');
  f.nextButton.dispatch('click');
  assert.equal(f.pager.index, 1);
  assert.equal(f.pages[1].dataset.direction, 'forward');
  assert.equal(f.nextButton.disabled, true);
  assert.equal(f.nextButton.textContent, '결과 보기 →');
  f.state.result = true;
  f.pager.refresh();
  f.stepButtons[2].dispatch('click');
  assert.equal(f.pager.index, 2);
  assert.equal(f.nextButton.hidden, true);
  assert.equal(f.nextButton.disabled, true);
  assert.equal(f.stepButtons[2].getAttribute('aria-current'), 'step');
  f.previousButton.dispatch('click');
  assert.equal(f.pager.index, 1);
  assert.equal(f.pages[1].dataset.direction, 'backward');
  assert.equal(f.nextButton.hidden, false);
  assert.deepEqual(f.changes, [1, 2, 1]);
  f.pager.destroy();
});

test('refresh keeps the current page and emits no changes even when availability changes', () => {
  const f = setup({ result: true });
  assert.equal(f.pager.goTo(2), true);
  f.state.result = false;
  f.pager.refresh();
  assert.equal(f.pager.index, 2);
  assert.equal(f.pages[2].hidden, false);
  assert.equal(f.stepButtons[2].getAttribute('aria-disabled'), 'true');
  f.pager.goTo(2);
  f.pager.refresh();
  for (const invalid of [-1, 3, 1.5, NaN, '1']) assert.equal(f.pager.goTo(invalid), false);
  assert.deepEqual(f.changes, [2]);
  f.pager.destroy();
});

test('busy state prevents programmatic navigation, clicks, arrows and swipes, including an in-flight gesture', () => {
  const f = setup({ result: true, busy: true });
  assert.equal(f.pager.goTo(1), false);
  f.stepButtons[2].dispatch('click');
  f.nextButton.dispatch('click');
  f.stepButtons[0].dispatch('keydown', { key: 'ArrowRight' });
  f.swipe(-100);
  assert.equal(f.pager.index, 0);
  assert.equal(f.nextButton.disabled, true);
  assert.ok(f.stepButtons.every(button => button.getAttribute('aria-disabled') === 'true'));
  assert.ok(f.stepButtons.every(button => button.disabled));
  f.state.busy = false;
  f.pager.refresh();
  f.gestureTarget.dispatch('pointerdown', { pointerId: 4, clientX: 150, clientY: 150, button: 0 });
  f.state.busy = true;
  f.gestureTarget.dispatch('pointerup', { pointerId: 4, clientX: 50, clientY: 150 });
  assert.equal(f.pager.index, 0);
  assert.deepEqual(f.changes, []);
  f.pager.destroy();
});

test('horizontal swipes navigate only one allowed page, while vertical, short and diagonal motion remain ordinary scrolling', () => {
  const f = setup();
  for (const [dx, dy] of [[-49, 0], [-70, 100], [-60, 40], [20, -100]]) {
    assert.equal(f.swipe(dx, dy).defaultPrevented, false);
    assert.equal(f.pager.index, 0);
  }
  assert.equal(f.swipe(-100, 10).defaultPrevented, true);
  assert.equal(f.pager.index, 1);
  assert.equal(f.swipe(-150).defaultPrevented, false, 'results cannot be opened before they exist');
  assert.equal(f.pager.index, 1);
  assert.equal(f.swipe(100, 10).defaultPrevented, true);
  assert.equal(f.pager.index, 0);
  f.swipe(-100, 0, { move: [5, 30] });
  assert.equal(f.pager.index, 0, 'a gesture that already began vertical scrolling must stay scrolling');
  f.pager.destroy();
});

test('inputs and nested interactive or editable targets never initiate or finish a page swipe', () => {
  const f = setup({ result: true });
  for (const tag of ['input', 'textarea', 'select', 'button', 'a', 'label', 'summary']) {
    const target = new Element(tag, f.gestureTarget), child = new Element('span', target);
    assert.equal(f.swipe(-120, 0, { target: child }).defaultPrevented, false);
    assert.equal(f.pager.index, 0, tag);
    f.swipe(-120, 0, { endTarget: child });
    assert.equal(f.pager.index, 0, `ending on ${tag}`);
  }
  const editable = new Element('div', f.gestureTarget);
  editable.setAttribute('contenteditable', '');
  f.swipe(-120, 0, { target: new Element('span', editable) });
  assert.equal(f.pager.index, 0);
  const textField = new Element('textarea');
  textField.dispatch('keydown', { key: 'ArrowRight' });
  assert.equal(f.pager.index, 0);
  f.stepButtons[0].dispatch('keydown', { key: 'ArrowRight', target: textField });
  assert.equal(f.pager.index, 0);
  f.stepButtons[0].dispatch('keydown', { key: 'ArrowRight' });
  assert.equal(f.pager.index, 1);
  assert.equal(f.stepButtons[1].focused, true);
  f.pager.destroy();
});

test('pointer cancellation, secondary pointers and destroy leave no latent navigation or listeners', () => {
  const f = setup({ result: true });
  f.gestureTarget.dispatch('pointerdown', { pointerId: 1, clientX: 150, clientY: 150, button: 0 });
  f.gestureTarget.dispatch('pointercancel', { pointerId: 1 });
  f.gestureTarget.dispatch('pointerup', { pointerId: 1, clientX: 20, clientY: 150 });
  assert.equal(f.pager.index, 0);
  f.gestureTarget.dispatch('pointerdown', { pointerId: 1, clientX: 150, clientY: 150, button: 0 });
  f.gestureTarget.dispatch('pointerdown', { pointerId: 2, isPrimary: false, clientX: 180, clientY: 150 });
  f.gestureTarget.dispatch('pointerup', { pointerId: 1, clientX: 20, clientY: 150 });
  assert.equal(f.pager.index, 0);
  const elements = [...f.stepButtons, f.previousButton, f.nextButton, f.gestureTarget];
  assert.ok(elements.every(element => element.listenerCount > 0));
  f.pager.destroy();
  f.pager.destroy();
  assert.ok(elements.every(element => element.listenerCount === 0));
  f.nextButton.dispatch('click');
  f.swipe(-120);
  f.pager.refresh();
  assert.equal(f.pager.goTo(1), false);
  assert.equal(f.pager.index, 0);
  assert.deepEqual(f.changes, []);
});

test('only the immediate synthetic click after a successful swipe is suppressed, without consuming new control taps', () => {
  const f = setup({ result: true });
  const oldCanvas = new Element('canvas', f.gestureTarget);
  f.swipe(-100, 0, { target: oldCanvas });
  assert.equal(f.pager.index, 1);
  const keyboard = f.gestureTarget.dispatch('click', { target: oldCanvas, detail: 0 });
  assert.equal(keyboard.defaultPrevented, false);
  const generated = f.gestureTarget.dispatch('click', { target: oldCanvas, detail: 1, clientX: 50, clientY: 150 });
  assert.equal(generated.defaultPrevented, true);
  assert.equal(generated.propagationStopped, true);
  assert.equal(generated.immediatePropagationStopped, true);
  const second = f.gestureTarget.dispatch('click', { target: oldCanvas, detail: 1, clientX: 50, clientY: 150 });
  assert.equal(second.defaultPrevented, false, 'suppression must be one-shot');

  f.pager.goTo(0);
  f.swipe(-100, 0, { target: oldCanvas });
  const button = new Element('button', f.gestureTarget);
  f.gestureTarget.dispatch('pointerdown', { target: button, pointerId: 2, clientX: 50, clientY: 150, button: 0 });
  const tap = f.gestureTarget.dispatch('click', { target: button, detail: 1, clientX: 50, clientY: 150 });
  assert.equal(tap.defaultPrevented, false, 'a new pointer interaction must not inherit suppression');

  f.pager.goTo(0);
  f.swipe(-100, 150, { target: oldCanvas });
  const vertical = f.gestureTarget.dispatch('click', { target: oldCanvas, detail: 1, clientX: 50, clientY: 300 });
  assert.equal(vertical.defaultPrevented, false);
  f.swipe(-100, 0, { target: oldCanvas });
  f.pager.destroy();
  const afterDestroy = f.gestureTarget.dispatch('click', { target: oldCanvas, detail: 1, clientX: 50, clientY: 150 });
  assert.equal(afterDestroy.defaultPrevented, false);
  assert.equal(f.gestureTarget.listenerCount, 0);
});
