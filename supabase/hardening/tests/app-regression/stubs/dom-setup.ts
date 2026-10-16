// jsdom als browser voor componenttests (t18). Moet vóór react-dom geladen worden. setInterval/clearInterval van het
// venster worden vastgelegd (geen echte tijd): de test roept de timers zelf aan.
// @ts-ignore
import { JSDOM } from "jsdom";
const dom = new JSDOM("<!doctype html><html><body><div id='root'></div></body></html>", { pretendToBeVisual: true, url: "http://localhost/" });
const g = globalThis as any;
g.window = dom.window; g.document = dom.window.document; g.HTMLElement = dom.window.HTMLElement;
g.IS_REACT_ACT_ENVIRONMENT = true;
g.__timers = new Map<number, { fn: () => void; ms: number }>();
let next = 1;
dom.window.setInterval = ((fn: () => void, ms: number) => { const id = next++; g.__timers.set(id, { fn, ms }); return id; }) as any;
dom.window.clearInterval = ((id: number) => { g.__timers.delete(id); }) as any;
g.__setVisible = (v: boolean) => {
  Object.defineProperty(dom.window.document, "visibilityState", { value: v ? "visible" : "hidden", configurable: true });
  dom.window.document.dispatchEvent(new dom.window.Event("visibilitychange"));
};
