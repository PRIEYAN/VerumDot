// ==========================================================
// Profile dropdown — mockup behavior
// Alert thresholds: temp > 75°C, any other meter > 90%
// ==========================================================

const TEMP_ALERT = 75;
const METER_ALERT = 90;

// ---------------- avatar upload ----------------

const avatarBtn = document.getElementById('avatarBtn');
const avatarInput = document.getElementById('avatarInput');
const avatarImg = document.getElementById('avatarImg');
const avatarFallback = document.getElementById('avatarFallback');

avatarBtn.addEventListener('click', () => avatarInput.click());

avatarInput.addEventListener('change', () => {
  const file = avatarInput.files && avatarInput.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = (e) => {
    avatarImg.src = e.target.result;
    avatarImg.hidden = false;
    avatarFallback.hidden = true;
  };
  reader.readAsDataURL(file);
});

// ---------------- editable username ----------------

const nameDisplay = document.getElementById('nameDisplay');
const nameInput = document.getElementById('nameInput');
const nameEditBtn = document.getElementById('nameEditBtn');

function enterNameEdit() {
  nameInput.value = nameDisplay.textContent;
  nameDisplay.hidden = true;
  nameInput.hidden = false;
  nameInput.focus();
  nameInput.select();
}

function commitNameEdit() {
  const value = nameInput.value.trim();
  if (value) {
    nameDisplay.textContent = value;
    avatarFallback.textContent = value[0].toUpperCase();
  }
  nameInput.hidden = true;
  nameDisplay.hidden = false;
}

nameEditBtn.addEventListener('click', enterNameEdit);
nameDisplay.addEventListener('dblclick', enterNameEdit);

nameInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') commitNameEdit();
  if (e.key === 'Escape') { nameInput.hidden = true; nameDisplay.hidden = false; }
});
nameInput.addEventListener('blur', commitNameEdit);

// ---------------- system stats: alert coloring ----------------

function evaluateStatRow(row) {
  const fill = row.querySelector('.meter-fill');
  const value = parseFloat(fill.style.width); // percentage used for both meter width and threshold
  const limit = row.dataset.unit === 'deg' ? TEMP_ALERT : METER_ALERT;
  // For temp we store the actual reading in the value text (°C) but drive
  // the bar width as a percentage; read the printed number for the real check.
  let reading = value;
  if (row.dataset.unit === 'deg') {
    const text = row.querySelector('.stat-value').textContent;
    reading = parseFloat(text);
  }
  row.classList.toggle('is-alert', reading > limit);
}

document.querySelectorAll('.stat-row').forEach(evaluateStatRow);

// ---------------- todo list ----------------

const todoList = document.getElementById('todoList');
const todoInput = document.getElementById('todoInput');
const todoCount = document.getElementById('todoCount');

let todos = [
  { text: 'push waybar dropdown mockup', done: true },
  { text: 'fix battery-alert threshold', done: true },
  { text: 'wire rofi theme for profile popup', done: false },
  { text: 'review PR #42', done: false },
  { text: 'clean up gtk.css leftovers', done: false },
];

function renderTodos() {
  todoList.innerHTML = '';

  todos.forEach((todo, index) => {
    const item = document.createElement('div');
    item.className = 'todo-item';

    const box = document.createElement('span');
    box.className = 'todo-box' + (todo.done ? ' is-checked' : '');
    box.addEventListener('click', () => {
      todo.done = !todo.done;
      renderTodos();
    });

    const text = document.createElement('span');
    text.className = 'todo-text' + (todo.done ? ' is-checked' : '');
    text.textContent = todo.text;
    text.addEventListener('click', () => {
      todo.done = !todo.done;
      renderTodos();
    });

    const remove = document.createElement('button');
    remove.className = 'todo-remove';
    remove.textContent = '×';
    remove.title = 'Remove';
    remove.addEventListener('click', (e) => {
      e.stopPropagation();
      todos.splice(index, 1);
      renderTodos();
    });

    item.appendChild(box);
    item.appendChild(text);
    item.appendChild(remove);
    todoList.appendChild(item);
  });

  const done = todos.filter(t => t.done).length;
  todoCount.textContent = `${done}/${todos.length}`;
}

function addTodo(text) {
  const trimmed = text.trim();
  if (!trimmed) return;
  todos.push({ text: trimmed, done: false });
  renderTodos();
}

todoInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    addTodo(todoInput.value);
    todoInput.value = '';
  }
});

renderTodos();

// ---------------- timer / stopwatch ----------------

const timerDisplay = document.getElementById('timerDisplay');
const timerToggle = document.getElementById('timerToggle');
const timerReset = document.getElementById('timerReset');

let elapsedMs = 0;
let running = false;
let tickHandle = null;
let lastTick = 0;

function formatTime(ms) {
  const totalSeconds = Math.floor(ms / 1000);
  const h = String(Math.floor(totalSeconds / 3600)).padStart(2, '0');
  const m = String(Math.floor((totalSeconds % 3600) / 60)).padStart(2, '0');
  const s = String(totalSeconds % 60).padStart(2, '0');
  return `${h}:${m}:${s}`;
}

function tick() {
  const now = performance.now();
  elapsedMs += now - lastTick;
  lastTick = now;
  timerDisplay.textContent = formatTime(elapsedMs);
}

function startTimer() {
  running = true;
  lastTick = performance.now();
  tickHandle = setInterval(tick, 250);
  timerToggle.textContent = '⏸';
  timerToggle.title = 'Pause';
  timerToggle.classList.add('is-running');
}

function pauseTimer() {
  running = false;
  clearInterval(tickHandle);
  timerToggle.textContent = '▶';
  timerToggle.title = 'Start';
  timerToggle.classList.remove('is-running');
}

timerToggle.addEventListener('click', () => {
  if (running) pauseTimer();
  else startTimer();
});

timerReset.addEventListener('click', () => {
  pauseTimer();
  elapsedMs = 0;
  timerDisplay.textContent = formatTime(elapsedMs);
});
