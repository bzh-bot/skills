/* annotate.js — in-page annotation layer for workflow-do tours and video captures.
 *
 * WHY IN-PAGE (user directive 2026-10-01, restated 2026-10-19): annotations drawn in the
 * browser are captured by BOTH `agent-browser screenshot` and the video capture, move with
 * the page (scroll/resize), and need no pixel maths on a PNG afterwards. **There is no
 * ImageMagick fallback and no post-processing of a captures image.** Painting boxes onto a
 * PNG afterwards is a different artefact: it does not follow the page, it cannot be verified
 * against the element, and it silently disagrees with the video. If in-page injection fails
 * (the page refuses injected styles, CSP blocks them, the wrong target), the annotation
 * GATE FAILS (`scripts/annotate-shot.sh` exits non-zero, `scripts/check-annotations.sh`
 * rejects the file) and the stage reports it. It must never fall back to painting pixels.
 *
 * Evidence: every draw increments `window.__wfAnnotState.marks` and mount sets
 * `document.documentElement.dataset.wfAnnot = 'mounted'`. `annotate-shot.sh` records that
 * state in `$SCREENSHOTS_DIR/annotations.json` next to the screenshot's sha256, and
 * `check-annotations.sh` rejects any file without it. A screenshot is annotated only when
 * this layer was mounted FOR THAT CAPTURE and drew at least one mark.
 *
 * Inject once per page with:   agent-browser ... eval --stdin < annotate.js
 * Then drive it with:          agent-browser ... eval "__wfAnnot.box('.foo', {label:'BEFORE: x'})"
 *
 * API (all return a short string so it is safe to call through `agent-browser eval`):
 *   __wfAnnot.mount()                    idempotent: styles + overlay + fake cursor → 'mounted' | 'style-blocked'
 *   __wfAnnot.status()                   JSON evidence: mounted / marks / styleApplied / timestamps
 *   __wfAnnot.unmount()                  remove everything (leave the page as found)
 *   __wfAnnot.clear()                    remove boxes/arrows/labels/banner, keep cursor; resets the mark counter
 *   __wfAnnot.cursor(x, y)               move the pointer (animated, matches video beats)
 *   __wfAnnot.click(x, y)                click ripple at a point
 *   __wfAnnot.box(target, opts)          rounded box around a selector|element + optional label
 *                                        opts: {label, color: 'before'|'after'|'accent', padding}
 *   __wfAnnot.arrow(from, to, opts)      arrow between two selectors|elements (or {x,y})
 *   __wfAnnot.label(text, opts)          floating label at {x,y} (default: near the last box)
 *   __wfAnnot.banner(kind, text)         big corner banner: kind 'before'|'after'
 *   __wfAnnot.dump()                     JSON summary of what is currently drawn
 */
(() => {
  if (window.__wfAnnot) return 'exists'

  const COLORS = { before: '#EF4444', after: '#22C55E', accent: '#38BDF8', ink: '#111827' }
  const Z = 2147483647

  const style = document.createElement('style')
  style.id = 'wf-annot-style'
  style.textContent = `
    #wf-annot-root{position:fixed;inset:0;z-index:${Z - 2};pointer-events:none}
    .wf-annot-box{position:fixed;border:4px solid;border-radius:10px;box-sizing:border-box;
      box-shadow:0 0 0 2px rgba(255,255,255,.85) inset,0 2px 10px rgba(0,0,0,.25)}
    .wf-annot-tag{position:fixed;max-width:46vw;padding:6px 12px;border-radius:999px;color:#fff;
      font:600 15px/1.35 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
      white-space:nowrap;overflow:hidden;text-overflow:ellipsis;box-shadow:0 2px 8px rgba(0,0,0,.35)}
    .wf-annot-arrow{position:fixed;overflow:visible;pointer-events:none}
    .wf-annot-banner{position:fixed;left:24px;top:24px;padding:10px 18px;border-radius:12px;color:#fff;
      font:800 20px/1.2 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
      letter-spacing:.04em;text-transform:uppercase;box-shadow:0 4px 14px rgba(0,0,0,.35)}
    #demo-cursor{position:fixed;left:0;top:0;width:22px;height:22px;z-index:${Z};pointer-events:none;
      transition:transform .55s cubic-bezier(.22,.61,.36,1);filter:drop-shadow(0 1px 2px rgba(0,0,0,.55))}
    .demo-ripple{position:fixed;z-index:${Z - 1};pointer-events:none;width:16px;height:16px;margin:-8px 0 0 -8px;
      border-radius:50%;background:rgba(56,189,248,.35);box-shadow:0 0 0 2px rgba(56,189,248,.95);
      animation:demo-ripple .8s ease-out forwards}
    @keyframes demo-ripple{from{transform:scale(.55);opacity:1}to{transform:scale(4.4);opacity:0}}
  `
  document.head.appendChild(style)

  const root = document.createElement('div')
  root.id = 'wf-annot-root'
  document.body.appendChild(root)

  // ── evidence marker ───────────────────────────────────────────────────────
  // The overlay only counts as an annotation if the styles actually applied: a CSP
  // that blocks the injected <style> leaves an invisible layer, and a PNG captured
  // over it looks unannotated. `styleApplied()` is the difference between "mounted"
  // and "the page refused us" — the gate in annotate-shot.sh fails on the latter.
  const styleApplied = () => {
    try {
      const cs = getComputedStyle(root)
      return cs.position === 'fixed' && cs.pointerEvents === 'none'
    } catch (_) { return false }
  }
  const STATE = window.__wfAnnotState = {
    v: 1,
    mountedAt: new Date().toISOString(),
    marks: 0,
    lastMarkAt: '',
    lastKind: '',
  }
  const mark = (kind) => {
    STATE.marks += 1
    STATE.lastMarkAt = new Date().toISOString()
    STATE.lastKind = kind
  }
  if (styleApplied()) document.documentElement.dataset.wfAnnot = 'mounted'

  // ── fake pointer (same visual language as the video's beat layer) ──
  const mountCursor = () => {
    if (document.getElementById('demo-cursor')) return
    const c = document.createElement('div')
    c.id = 'demo-cursor'
    c.innerHTML =
      '<svg viewBox="0 0 24 24" width="22" height="22"><path d="M4 2 L20 12 L12 13.2 L9.2 21 Z" ' +
      'fill="#ffffff" stroke="#111827" stroke-width="1.4"/></svg>'
    c.style.transform = `translate(${Math.round(innerWidth / 2)}px, ${Math.round(innerHeight / 2)}px)`
    document.body.appendChild(c)
  }

  // ── geometry ───────────────────────────────────────────────────────────────
  const resolve = (t) => {
    if (!t) return null
    if (typeof t === 'string') return document.querySelector(t)
    if (t instanceof Element) return t
    return null
  }
  const point = (t) => {
    if (t && typeof t === 'object' && 'x' in t) return { x: t.x, y: t.y }
    const el = resolve(t)
    if (!el) return null
    const r = el.getBoundingClientRect()
    return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) }
  }
  const rect = (t, pad = 6) => {
    const el = resolve(t)
    if (!el) return null
    const r = el.getBoundingClientRect()
    return { x: r.left - pad, y: r.top - pad, w: r.width + pad * 2, h: r.height + pad * 2 }
  }

  const drawn = []          // { node, redraw }
  const register = (node, redraw) => {
    drawn.push({ node, redraw })
    redraw()
  }
  const redrawAll = () => { for (const d of drawn) { try { d.redraw() } catch (_) {} } }
  addEventListener('scroll', redrawAll, { passive: true, capture: true })
  addEventListener('resize', redrawAll, { passive: true })

  const color = (c) => COLORS[c] || c || COLORS.accent

  // ── drawing primitives ────────────────────────────────────────────────────
  const drawBox = (target, opts = {}) => {
    const node = document.createElement('div')
    node.className = 'wf-annot-box'
    root.appendChild(node)
    const c = color(opts.color)
    let tag = null
    if (opts.label) {
      tag = document.createElement('div')
      tag.className = 'wf-annot-tag'
      tag.textContent = opts.label
      tag.style.background = c
      root.appendChild(tag)
    }
    const redraw = () => {
      const r = rect(target, opts.padding ?? 6)
      if (!r) return
      Object.assign(node.style, { left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px`, borderColor: c })
      if (tag) {
        const top = r.y - 34 < 8 ? r.y + r.h + 8 : r.y - 34
        Object.assign(tag.style, { left: `${Math.max(8, r.x)}px`, top: `${top}px` })
      }
    }
    register(node, redraw)
    if (tag) drawn.push({ node: tag, redraw })
    if (rect(target)) mark('box')
    return rect(target) ? 'ok' : 'not-found'
  }

  const drawArrow = (from, to, opts = {}) => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('class', 'wf-annot-arrow')
    const c = color(opts.color)
    const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs')
    const marker = document.createElementNS('http://www.w3.org/2000/svg', 'marker')
    marker.setAttribute('id', 'wf-annot-head')
    marker.setAttribute('markerWidth', '8'); marker.setAttribute('markerHeight', '8')
    marker.setAttribute('refX', '6'); marker.setAttribute('refY', '3'); marker.setAttribute('orient', 'auto')
    const mp = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    mp.setAttribute('d', 'M0,0 L6,3 L0,6 Z'); mp.setAttribute('fill', c)
    marker.appendChild(mp); defs.appendChild(marker); svg.appendChild(defs)
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line')
    line.setAttribute('stroke', c); line.setAttribute('stroke-width', '4')
    line.setAttribute('stroke-linecap', 'round'); line.setAttribute('marker-end', 'url(#wf-annot-head)')
    svg.appendChild(line)
    root.appendChild(svg)
    const redraw = () => {
      const a = point(from), b = point(to)
      if (!a || !b) return
      const x = Math.min(a.x, b.x) - 40, y = Math.min(a.y, b.y) - 40
      const w = Math.abs(a.x - b.x) + 80, h = Math.abs(a.y - b.y) + 80
      Object.assign(svg.style, { left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` })
      svg.setAttribute('viewBox', `${x} ${y} ${w} ${h}`)
      line.setAttribute('x1', a.x); line.setAttribute('y1', a.y)
      line.setAttribute('x2', b.x); line.setAttribute('y2', b.y)
    }
    register(svg, redraw)
    if (point(from) && point(to)) mark('arrow')
    return point(from) && point(to) ? 'ok' : 'not-found'
  }

  const last = { x: 320, y: 220 }
  const drawLabel = (text, opts = {}) => {
    const node = document.createElement('div')
    node.className = 'wf-annot-tag'
    node.textContent = text
    node.style.background = color(opts.color)
    root.appendChild(node)
    const p = (opts.x != null ? { x: opts.x, y: opts.y } : last)
    Object.assign(node.style, { left: `${p.x}px`, top: `${p.y}px` })
    drawn.push({ node, redraw: () => { node.style.left = `${p.x}px`; node.style.top = `${p.y}px` } })
    mark('label')
    return 'ok'
  }

  const drawBanner = (kind, text) => {
    const node = document.createElement('div')
    node.className = 'wf-annot-banner'
    node.textContent = text || (kind === 'after' ? 'AFTER' : 'BEFORE')
    node.style.background = color(kind === 'after' ? 'after' : 'before')
    root.appendChild(node)
    drawn.push({ node, redraw: () => {} })
    mark('banner')
    return 'ok'
  }

  // ── public API ────────────────────────────────────────────────────────────
  window.__wfAnnot = {
    mount: () => {
      root.isConnected || document.body.appendChild(root)
      mountCursor()
      if (styleApplied()) document.documentElement.dataset.wfAnnot = 'mounted'
      return styleApplied() ? 'mounted' : 'style-blocked'
    },
    unmount: () => {
      try {
        root.remove(); style.remove(); document.getElementById('demo-cursor')?.remove()
        delete document.documentElement.dataset.wfAnnot
      } catch (_) {}
      delete window.__wfAnnot
      delete window.__wfAnnotState
      return 'unmounted'
    },
    clear: () => {
      for (const d of drawn) { try { d.node.remove() } catch (_) {} }
      drawn.length = 0
      STATE.marks = 0
      return 'cleared'
    },
    status: () => JSON.stringify({
      mounted: root.isConnected && styleApplied(),
      overlay: root.isConnected,
      styleApplied: styleApplied(),
      dataset: document.documentElement.dataset.wfAnnot || '',
      marks: STATE.marks,
      lastKind: STATE.lastKind,
      mountedAt: STATE.mountedAt,
      lastMarkAt: STATE.lastMarkAt,
      url: location.href,
      v: STATE.v,
    }),
    cursor: (x, y) => {
      mountCursor()
      const c = document.getElementById('demo-cursor')
      if (c) c.style.transform = `translate(${Math.round(x)}px, ${Math.round(y)}px)`
      last.x = Math.round(x); last.y = Math.round(y)
      return 'ok'
    },
    click: (x, y) => {
      const d = document.createElement('div')
      d.className = 'demo-ripple'
      d.style.left = `${Math.round(x)}px`; d.style.top = `${Math.round(y)}px`
      document.body.appendChild(d); setTimeout(() => d.remove(), 900)
      __wfAnnot.cursor(x, y)
      return 'ok'
    },
    box: drawBox,
    arrow: drawArrow,
    label: drawLabel,
    banner: drawBanner,
    dump: () => JSON.stringify({
      boxes: drawn.filter((d) => d.node.className === 'wf-annot-box').length,
      others: drawn.filter((d) => d.node.className !== 'wf-annot-box').length,
      marks: STATE.marks,
      styleApplied: styleApplied(),
    }),
  }

  mountCursor()
  return styleApplied() ? 'mounted' : 'style-blocked'
})()
