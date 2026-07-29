// Static site, no framework, no build step. This file stays small on purpose.
//
// Everything here is progressive enhancement: the page is complete and readable
// with this file blocked. Nothing below creates content, only refines it.

// The copyright year is stamped at render time so the footer never goes stale
// between deploys.
document.getElementById("year").textContent = new Date().getFullYear();

/* --------------------------------------------------------------- reveal -- */

// The hidden half of the reveal lives behind .js-reveal, and only this line
// turns it on. If the script fails to load, or throws before here, the CSS rule
// never matches and every section renders plainly visible rather than blank.
// That ordering is the whole safety property, so this stays at the top.
document.documentElement.classList.add("js-reveal");

const reveals = document.querySelectorAll(".reveal");

// Elements reveal once and stay revealed; unobserving on entry keeps the
// callback from re-firing on every scroll past an element already shown.
const revealObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("reveal--visible");
      revealObserver.unobserve(entry.target);
    }
  },
  // Fires slightly before the element's top edge reaches the viewport bottom,
  // so the transition is already underway by the time it is properly in view.
  { rootMargin: "0px 0px -10% 0px", threshold: 0.05 },
);

for (const el of reveals) revealObserver.observe(el);

/* --------------------------------------------------------------- header -- */

// The nav pill is transparent over the hero and gains a surface once it starts
// overlapping content. Reading scrollY in a rAF callback keeps the layout query
// out of the scroll handler itself, which is what makes this cheap enough to
// run passively on every scroll event.
const header = document.querySelector(".site-header");
let ticking = false;

function syncHeader() {
  header.classList.toggle("site-header--scrolled", window.scrollY > 24);
  ticking = false;
}

addEventListener(
  "scroll",
  () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(syncHeader);
  },
  { passive: true },
);

syncHeader(); // A reload partway down the page must not start in the top state.

/* ---------------------------------------------------------- mobile nav -- */

// A disclosure, not a modal: the page behind it stays scrollable and focus is
// free to leave, so there is no trap here. Closed is display:none rather than
// off screen, which keeps the panel's links out of the tab order.
const navToggle = document.querySelector(".nav__toggle");
const navMenu = document.getElementById("primary-menu");

// aria-expanded is the state; the class only paints. Reading back off the
// attribute is what stops the two from drifting apart.
const navIsOpen = () => navToggle.getAttribute("aria-expanded") === "true";

function setNav(open) {
  navToggle.setAttribute("aria-expanded", String(open));
  header.classList.toggle("site-header--nav-open", open);
}

navToggle.addEventListener("click", () => setNav(!navIsOpen()));

// These are same-document anchors, so nothing navigates and nothing else would
// close the panel over the section just chosen.
navMenu.addEventListener("click", (event) => {
  if (event.target.closest("a")) setNav(false);
});

addEventListener("keydown", (event) => {
  if (event.key !== "Escape" || !navIsOpen()) return;
  setNav(false);
  navToggle.focus(); // Closing must not strand focus inside display:none.
});

addEventListener("pointerdown", (event) => {
  if (!navIsOpen() || header.contains(event.target)) return;
  setNav(false);
});

// Rotating to landscape can cross the breakpoint with the panel still open.
matchMedia("(min-width: 64rem)").addEventListener("change", () => setNav(false));

/* ------------------------------------------------------------ active nav -- */

// Maps each section to the nav link that points at it, so the observer callback
// is a lookup rather than a query.
const linksBySection = new Map();
for (const link of document.querySelectorAll(".nav__link")) {
  const section = document.querySelector(link.getAttribute("href"));
  if (section) linksBySection.set(section, link);
}

// The negative top margin pulls the observer's viewport down past the fixed
// header, and the negative bottom margin narrows it to a band across the upper
// middle of the screen. A section counts as current only while it crosses that
// band, which prevents two sections from being active at once.
const navObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      const link = linksBySection.get(entry.target);
      if (!link) continue;
      if (entry.isIntersecting) {
        for (const other of linksBySection.values()) {
          other.classList.remove("nav__link--active");
        }
        link.classList.add("nav__link--active");
      }
    }
  },
  { rootMargin: "-20% 0px -70% 0px" },
);

for (const section of linksBySection.keys()) navObserver.observe(section);

/* ------------------------------------------------------ hero spotlight -- */

// A soft light that trails the cursor across the hero. Purely decorative, so
// it is driven entirely from here: with this file blocked the blob parks at the
// resting offset baked into the CSS fallback and the hero still looks finished.
const hero = document.getElementById("hero");
const spotlight = document.querySelector(".hero__spotlight");

// Checked once rather than per-event. Anyone who has asked the OS to reduce
// motion gets the static resting position and never has a listener attached,
// which is also the cheapest possible path.
const stillness = matchMedia("(prefers-reduced-motion: reduce)");

let pointerX = 0;
let pointerY = 0;
let spotQueued = false;

// Where the light sits before the pointer has ever moved, and wherever it is
// sent on resize. Off to the right and high up, so the hero reads as lit from
// above rather than centred and symmetrical.
function restPosition() {
  pointerX = window.innerWidth * 0.72;
  pointerY = Math.min(window.innerHeight * 0.34, 360) + window.scrollY;
}

function paintSpotlight() {
  spotQueued = false;
  // The reference positions the blob straight from viewport coordinates, which
  // makes it drift once the page scrolls. Converting to a position within the
  // hero keeps the light under the cursor at any scroll offset. offsetTop is a
  // document-relative measure, so it is stable while scrolling.
  spotlight.style.setProperty("--spot-x", `${pointerX}px`);
  spotlight.style.setProperty("--spot-y", `${pointerY - hero.offsetTop}px`);
}

// Coalesces a burst of pointermove events into one write per animation frame.
// Without this the browser is asked to recompute a 64px blur far more often
// than it can paint.
function queueSpotlight() {
  if (spotQueued) return;
  spotQueued = true;
  requestAnimationFrame(paintSpotlight);
}

function trackPointer(event) {
  pointerX = event.clientX;
  pointerY = event.clientY + window.scrollY;
  queueSpotlight();
}

function syncSpotlightMode() {
  removeEventListener("pointermove", trackPointer);
  restPosition();
  paintSpotlight();
  if (!stillness.matches) {
    addEventListener("pointermove", trackPointer, { passive: true });
  }
}

addEventListener("resize", () => {
  restPosition();
  queueSpotlight();
});

// Re-evaluated live, so toggling the OS setting takes effect without a reload.
stillness.addEventListener("change", syncSpotlightMode);

syncSpotlightMode();

/* -------------------------------------------------------------- counter -- */

// Phase 3 wires the visitor counter here: fetch the count API and write the
// result into #visitor-count, leaving the em dash fallback in place on failure.
