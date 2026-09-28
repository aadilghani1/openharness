// Native controls replace the old artifact host's injected control panel.
(() => {
  const reduced = matchMedia("(prefers-reduced-motion: reduce)"),
    dark = matchMedia("(prefers-color-scheme: dark)");
  let motion = !reduced.matches;
  const listeners = new Set();
  window.Preview = {
    get motion() {
      return motion;
    },
    onMotion(fn) {
      listeners.add(fn);
    },
  };
  const instances = [];
  class ReviewControls {
    constructor({ onChange }) {
      this.onChange = onChange;
      this.bindings = [];
      instances.push(this);
    }
    field(label) {
      const wrapper = document.createElement("label");
      wrapper.className = "review-field";
      const caption = document.createElement("span");
      caption.textContent = label;
      wrapper.append(caption);
      document.getElementById("review-fields").append(wrapper);
      return wrapper;
    }
    bind(state, key, input, convert = String) {
      this.bindings.push({ state, key, input });
      input.addEventListener("input", () => {
        state[key] = convert(input.value);
        this.onChange();
        ReviewControls.refresh();
      });
      input.value = String(state[key]);
    }
    addSelect(state, key, { label, options }) {
      const wrapper = this.field(label),
        select = document.createElement("select");
      for (const item of options) {
        const option = document.createElement("option");
        option.value = typeof item === "string" ? item : item.value;
        option.textContent = typeof item === "string" ? item : item.label;
        select.append(option);
      }
      wrapper.append(select);
      this.bind(state, key, select);
    }
    addSlider(state, key, { label, min, max, step, unit = "" }) {
      const wrapper = this.field(label),
        input = document.createElement("input"),
        output = document.createElement("output");
      input.type = "range";
      input.min = min;
      input.max = max;
      input.step = step;
      wrapper.append(input, output);
      this.bind(state, key, input, Number);
      const update = () => {
        output.value = state[key] + " " + unit;
        input.setAttribute("aria-valuetext", output.value);
      };
      input.addEventListener("input", update);
      update();
    }
    addToggle(state, key, { label }) {
      const wrapper = this.field(label),
        input = document.createElement("input");
      input.type = "checkbox";
      input.checked = state[key];
      wrapper.append(input);
      this.bindings.push({ state, key, input });
      input.addEventListener("change", () => {
        state[key] = input.checked;
        this.onChange();
      });
    }
    static refresh() {
      for (const instance of instances)
        for (const { state, key, input } of instance.bindings) {
          if (input.type === "checkbox") input.checked = state[key];
          else input.value = String(state[key]);
        }
    }
  }
  window.ReviewControls = ReviewControls;
  document.addEventListener("DOMContentLoaded", () => {
    const theme = document.getElementById("review-theme"),
      toggle = document.getElementById("review-motion");
    const applyTheme = () => {
      document.documentElement.dataset.theme =
        theme.value === "system"
          ? dark.matches
            ? "dark"
            : "light"
          : theme.value;
    };
    theme.addEventListener("change", applyTheme);
    dark.addEventListener("change", applyTheme);
    applyTheme();
    const applyMotion = (value) => {
      motion = value;
      toggle.checked = value;
      listeners.forEach((fn) => fn(value));
    };
    toggle.checked = motion;
    toggle.addEventListener("change", () => applyMotion(toggle.checked));
    reduced.addEventListener("change", (event) => applyMotion(!event.matches));
  });
})();
