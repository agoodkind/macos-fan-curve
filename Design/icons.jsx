// Each icon is a function that returns SVG content for a 1024x1024 viewBox.
// Rendered at any size by wrapping in a sized <svg viewBox="0 0 1024 1024">.

const SHARED_DEFS = (
  <defs>
    <linearGradient id="tile" x1="120" y1="100" x2="890" y2="914" gradientUnits="userSpaceOnUse">
      <stop stopColor="#313D4B" />
      <stop offset="1" stopColor="#151C25" />
    </linearGradient>
    <linearGradient id="tileWarm" x1="120" y1="100" x2="890" y2="914" gradientUnits="userSpaceOnUse">
      <stop stopColor="#2B3340" />
      <stop offset="1" stopColor="#0F141C" />
    </linearGradient>
    <linearGradient id="glassStroke" x1="120" y1="100" x2="890" y2="914" gradientUnits="userSpaceOnUse">
      <stop stopColor="#566475" />
      <stop offset="1" stopColor="#27303A" />
    </linearGradient>
    <linearGradient id="curveBlue" x1="160" y1="0" x2="900" y2="0" gradientUnits="userSpaceOnUse">
      <stop stopColor="#62C8FF" />
      <stop offset="1" stopColor="#1B79F2" />
    </linearGradient>
    <linearGradient id="curveOrange" x1="500" y1="0" x2="900" y2="0" gradientUnits="userSpaceOnUse">
      <stop stopColor="#FFB268" />
      <stop offset="1" stopColor="#FF652D" />
    </linearGradient>
    <linearGradient id="curveCool2Hot" x1="160" y1="800" x2="900" y2="200" gradientUnits="userSpaceOnUse">
      <stop offset="0" stopColor="#62C8FF" />
      <stop offset="0.55" stopColor="#9BA8FF" />
      <stop offset="0.78" stopColor="#FFB268" />
      <stop offset="1" stopColor="#FF652D" />
    </linearGradient>
    <linearGradient id="plotFillBlue" x1="0" y1="200" x2="0" y2="900" gradientUnits="userSpaceOnUse">
      <stop offset="0" stopColor="#1B79F2" stopOpacity="0.35" />
      <stop offset="1" stopColor="#1B79F2" stopOpacity="0" />
    </linearGradient>
    <linearGradient id="plotFillHot" x1="0" y1="200" x2="0" y2="900" gradientUnits="userSpaceOnUse">
      <stop offset="0" stopColor="#FF652D" stopOpacity="0.45" />
      <stop offset="1" stopColor="#1B79F2" stopOpacity="0" />
    </linearGradient>
    <radialGradient id="plotFillHotV4" cx="0.85" cy="0.18" r="0.95" gradientUnits="objectBoundingBox">
      <stop offset="0" stopColor="#FF652D" stopOpacity="0.55" />
      <stop offset="0.45" stopColor="#FF8A4B" stopOpacity="0.22" />
      <stop offset="1" stopColor="#1B79F2" stopOpacity="0" />
    </radialGradient>
    <filter id="shadow" x="36" y="40" width="952" height="952" filterUnits="userSpaceOnUse" colorInterpolationFilters="sRGB">
      <feDropShadow dx="0" dy="28" stdDeviation="34" floodColor="#09111D" floodOpacity="0.2" />
    </filter>
    <filter id="innerHighlight" x="-10%" y="-10%" width="120%" height="120%">
      <feGaussianBlur stdDeviation="6" />
    </filter>
  </defs>
);

// Squircle tile shared by all variants
const Tile = ({ fill = "url(#tile)" }) => (
  <g filter="url(#shadow)">
    <rect x="96" y="96" width="832" height="832" rx="184" fill={fill} />
    <rect x="110" y="110" width="804" height="804" rx="170" stroke="url(#glassStroke)" strokeWidth="6" />
  </g>
);

// ─── V0: ORIGINAL (for comparison) ─────────────────────────────
function IconV0() {
  return (
    <>
      {SHARED_DEFS}
      <Tile />
      <rect x="154" y="202" width="536" height="620" rx="36" fill="#1A222C" />
      <rect x="170" y="218" width="504" height="588" rx="26" fill="#0D141D" opacity="0.12" />
      <rect x="154" y="202" width="536" height="620" rx="36" stroke="#425163" strokeWidth="3" />
      <rect x="726" y="202" width="140" height="620" rx="36" fill="#1B232E" />
      <rect x="726" y="202" width="140" height="620" rx="36" stroke="#3A4655" strokeWidth="3" />
      <g opacity="0.18" stroke="#4F7EAF" strokeWidth="2">
        {[260, 361, 462, 563, 664, 764].map((y) => <path key={y} d={`M218 ${y}H626`} />)}
        {[218, 300, 382, 464, 546, 626].map((x) => <path key={x} d={`M${x} 260V764`} />)}
      </g>
      <path d="M192 776C278 682 329 616 386 568C442 521 503 535 544 474C584 430 610 356 634 252"
        stroke="#F2F8FE" strokeWidth="42" strokeLinecap="round" strokeLinejoin="round" fill="none" />
      <path d="M192 776C278 682 329 616 386 568C442 521 503 535 544 474C547.2 470.1 550.4 465.9 553.4 461.4"
        stroke="url(#curveBlue)" strokeWidth="24" strokeLinecap="round" strokeLinejoin="round" fill="none" />
      <path d="M553.4 461.4C586 420 612 350 634 252"
        stroke="url(#curveOrange)" strokeWidth="24" strokeLinecap="round" strokeLinejoin="round" fill="none" />
      {[[192, 776], [313, 640], [428.5, 542.1], [553.4, 461.4], [634, 252]].map(([x, y], i) => (
        <g key={i}>
          <circle cx={x} cy={y} r="18" fill="#56B6FF" />
          <circle cx={x} cy={y} r="13" fill="#F6FBFF" />
        </g>
      ))}
      <circle cx="796" cy="327" r="16" fill="#38D06E" />
      <rect x="748" y="674" width="96" height="46" rx="23" fill="#2D8BFF" />
      <circle cx="816" cy="697" r="18" fill="#D9E7F8" />
    </>
  );
}

// ─── V1: HERO CURVE — strip the side panel, keep chart, enlarge curve ───
function IconV1() {
  return (
    <>
      {SHARED_DEFS}
      <Tile />
      {/* Single full-bleed plot area, no side rail */}
      <rect x="180" y="200" width="664" height="624" rx="40" fill="#141B24" />
      <rect x="180" y="200" width="664" height="624" rx="40" stroke="#425163" strokeWidth="4" />
      {/* Sparser grid */}
      <g opacity="0.22" stroke="#4F7EAF" strokeWidth="3">
        {[360, 512, 664].map((y) => <path key={y} d={`M210 ${y}H814`} />)}
        {[360, 512, 664].map((x) => <path key={x} d={`M${x} 230V794`} />)}
      </g>
      {/* Filled area under curve */}
      <path d="M210 780 C 320 700, 400 640, 480 560 C 560 480, 640 360, 814 230 L 814 794 L 210 794 Z"
        fill="url(#plotFillHot)" />
      {/* Chunky single curve */}
      <path d="M210 780 C 320 700, 400 640, 480 560 C 560 480, 640 360, 814 230"
        stroke="url(#curveCool2Hot)" strokeWidth="60" strokeLinecap="round" fill="none" />
      {/* 3 prominent dots only */}
      {[[210, 780], [480, 560], [814, 230]].map(([x, y], i) => (
        <g key={i}>
          <circle cx={x} cy={y} r="30" fill="#0E141C" />
          <circle cx={x} cy={y} r="22" fill="#F6FBFF" />
        </g>
      ))}
    </>
  );
}

// ─── V2: PURE CURVE — no chart frame, curve is the icon ─────────
function IconV2() {
  return (
    <>
      {SHARED_DEFS}
      <Tile />
      {/* Two faint axis ticks for context */}
      <g opacity="0.15" stroke="#7892AB" strokeWidth="6" strokeLinecap="round">
        <path d="M210 814 L 814 814" />
        <path d="M210 814 L 210 210" />
      </g>
      {/* Filled area */}
      <path d="M210 800 C 340 740, 430 660, 520 540 C 610 420, 680 290, 814 220 L 814 814 L 210 814 Z"
        fill="url(#plotFillHot)" />
      {/* Hero curve — fat */}
      <path d="M210 800 C 340 740, 430 660, 520 540 C 610 420, 680 290, 814 220"
        stroke="url(#curveCool2Hot)" strokeWidth="96" strokeLinecap="round" fill="none" />
      {/* End-cap dot */}
      <circle cx="814" cy="220" r="44" fill="#FFE7D2" />
      <circle cx="814" cy="220" r="28" fill="#FF652D" />
    </>
  );
}

// ─── V3: GLYPH — abstract curve mark, very small-friendly ───────
function IconV3() {
  return (
    <>
      {SHARED_DEFS}
      <Tile fill="url(#tileWarm)" />
      {/* One bold curve, centered, balanced */}
      <path d="M232 760 C 380 740, 460 660, 520 520 C 580 380, 660 280, 792 252"
        stroke="#0E141C" strokeWidth="118" strokeLinecap="round" fill="none" opacity="0.55" />
      <path d="M232 760 C 380 740, 460 660, 520 520 C 580 380, 660 280, 792 252"
        stroke="url(#curveCool2Hot)" strokeWidth="92" strokeLinecap="round" fill="none" />
    </>
  );
}

// ─── V4: SQUARE PLOT — size-aware (tier 1 simplest → tier 4 full) ──
function IconV4({ tier = 4 }) {
  const M = 220;
  const plotX = M, plotY = M, plotW = 1024 - 2 * M, plotH = 1024 - 2 * M;
  const gx0 = plotX, gx1 = plotX + plotW;
  const gy0 = plotY, gy1 = plotY + plotH;
  const cols = 6, rows = 6;
  const xs = Array.from({ length: cols + 1 }, (_, i) => gx0 + (gx1 - gx0) * (i / cols));
  const ys = Array.from({ length: rows + 1 }, (_, i) => gy0 + (gy1 - gy0) * (i / rows));
  const sx = gx0 + 90, sy = gy1 - 80;
  const ex = gx1 - 90, ey = gy0 + 80;
  const curveD = `M${sx} ${sy} C ${gx0 + 360} ${gy1 - 60}, ${gx1 - 360} ${gy0 + 60}, ${ex} ${ey}`;
  // Tier 1 / 2 curve: pulled in from the tile edges with breathing room
  const t1sx = 280, t1sy = 750, t1ex = 744, t1ey = 274;
  const t1d = `M${t1sx} ${t1sy} C 510 760, 514 264, ${t1ex} ${t1ey}`;
  const slW = 80, slH = 280;
  const slX = gx1 - slW - 36, slY = gy1 - slH - 36;
  const slCx = slX + slW / 2;

  // Tier 1 — favicon scale: just the curve, full-bleed, no frame/grid/dots/slider
  if (tier === 1) {
    return (
      <>
        {SHARED_DEFS}
        <Tile />
        <path d={t1d} stroke="url(#curveCool2Hot)" strokeWidth="170" strokeLinecap="round" fill="none" />
      </>
    );
  }

  // Tier 2 — menu bar: curve + 2 endpoint dots, full-bleed
  if (tier === 2) {
    return (
      <>
        {SHARED_DEFS}
        <Tile />
        <path d={t1d} stroke="url(#curveCool2Hot)" strokeWidth="150" strokeLinecap="round" fill="none" />
        <circle cx={t1sx} cy={t1sy} r="62" fill="#D2EBFF" />
        <circle cx={t1sx} cy={t1sy} r="40" fill="#1B79F2" />
        <circle cx={t1ex} cy={t1ey} r="62" fill="#FFE7D2" />
        <circle cx={t1ex} cy={t1ey} r="40" fill="#FF652D" />
      </>
    );
  }

  // Tier 3 — dock: + plot frame + heat glow (no grid, no slider)
  if (tier === 3) {
    return (
      <>
        {SHARED_DEFS}
        <defs>
          <clipPath id="v4PlotClip3">
            <rect x={plotX} y={plotY} width={plotW} height={plotH} rx="44" />
          </clipPath>
        </defs>
        <Tile />
        <rect x={plotX} y={plotY} width={plotW} height={plotH} rx="44" fill="#141B24" />
        <g clipPath="url(#v4PlotClip3)">
          <rect x={plotX} y={plotY} width={plotW} height={plotH} fill="url(#plotFillHotV4)" />
        </g>
        <rect x={plotX} y={plotY} width={plotW} height={plotH} rx="44" fill="none" stroke="#425163" strokeWidth="4" />
        <path d={curveD} stroke="url(#curveCool2Hot)" strokeWidth="160" strokeLinecap="round" fill="none" />
        <circle cx={sx} cy={sy} r="64" fill="#D2EBFF" />
        <circle cx={sx} cy={sy} r="42" fill="#1B79F2" />
        <circle cx={ex} cy={ey} r="64" fill="#FFE7D2" />
        <circle cx={ex} cy={ey} r="42" fill="#FF652D" />
      </>
    );
  }

  // Tier 4 — full: + grid lines + slider
  return (
    <>
      {SHARED_DEFS}
      <defs>
        <clipPath id="v4PlotClip">
          <rect x={plotX} y={plotY} width={plotW} height={plotH} rx="44" />
        </clipPath>
      </defs>
      <Tile />
      <rect x={plotX} y={plotY} width={plotW} height={plotH} rx="44" fill="#141B24" />
      <g clipPath="url(#v4PlotClip)">
        <g opacity="0.22" stroke="#4F7EAF" strokeWidth="3">
          {ys.slice(1, -1).map((y) => <path key={`h${y}`} d={`M${gx0} ${y}H${gx1}`} />)}
          {xs.slice(1, -1).map((x) => <path key={`v${x}`} d={`M${x} ${gy0}V${gy1}`} />)}
        </g>
        <rect x={plotX} y={plotY} width={plotW} height={plotH} fill="url(#plotFillHotV4)" />
      </g>
      <rect x={plotX} y={plotY} width={plotW} height={plotH} rx="44" fill="none" stroke="#425163" strokeWidth="4" />
      <path d={curveD} stroke="url(#curveCool2Hot)" strokeWidth="110" strokeLinecap="round" fill="none" />
      <circle cx={sx} cy={sy} r="50" fill="#D2EBFF" />
      <circle cx={sx} cy={sy} r="32" fill="#1B79F2" />
      <circle cx={ex} cy={ey} r="50" fill="#FFE7D2" />
      <circle cx={ex} cy={ey} r="32" fill="#FF652D" />
      <rect x={slX} y={slY} width={slW} height={slH} rx={slW / 2} fill="url(#curveCool2Hot)" opacity="0.9" />
      <circle cx={slCx} cy={slY + slH - 40} r="32" fill="#FFE7D2" />
      <circle cx={slCx} cy={slY + slH - 40} r="20" fill="#FF652D" />
    </>
  );
}

// ─── V5: BIG CURVE + 2 DOTS, NO FRAME ───────────────────────────
function IconV5() {
  return (
    <>
      {SHARED_DEFS}
      <Tile />
      {/* baseline + axis as dim guides */}
      <g opacity="0.18" stroke="#7892AB" strokeWidth="8" strokeLinecap="round">
        <path d="M220 820 L 804 820" />
      </g>
      <path d="M220 800 C 360 740, 440 660, 520 540 C 600 420, 680 290, 804 220 L 804 820 L 220 820 Z"
        fill="url(#plotFillHot)" />
      <path d="M220 800 C 360 740, 440 660, 520 540 C 600 420, 680 290, 804 220"
        stroke="url(#curveCool2Hot)" strokeWidth="84" strokeLinecap="round" fill="none" />
      {/* start (cool) and end (hot) markers */}
      <circle cx="220" cy="800" r="40" fill="#0E141C" />
      <circle cx="220" cy="800" r="26" fill="#62C8FF" />
      <circle cx="804" cy="220" r="40" fill="#0E141C" />
      <circle cx="804" cy="220" r="26" fill="#FF652D" />
    </>
  );
}

// ─── V6: STEPPED CURVE — fan profile silhouette ─────────────────
function IconV6() {
  return (
    <>
      {SHARED_DEFS}
      <Tile />
      {/* axes */}
      <g opacity="0.18" stroke="#7892AB" strokeWidth="6" strokeLinecap="round">
        <path d="M220 800 L 804 800" />
        <path d="M220 800 L 220 220" />
      </g>
      {/* Stepped fill */}
      <path d="M220 800 L 220 740 L 380 740 L 380 620 L 540 620 L 540 460 L 700 460 L 700 280 L 804 280 L 804 800 Z"
        fill="url(#plotFillHot)" />
      {/* Stepped stroke */}
      <path d="M220 740 L 380 740 L 380 620 L 540 620 L 540 460 L 700 460 L 700 280 L 804 280"
        stroke="url(#curveCool2Hot)" strokeWidth="50" strokeLinecap="round" strokeLinejoin="round" fill="none" />
    </>
  );
}

// ─── V7: MINIMAL — just curve, no tile content, max contrast ────
function IconV7() {
  return (
    <>
      {SHARED_DEFS}
      <Tile fill="url(#tileWarm)" />
      <path d="M200 800 Q 360 800, 520 520 T 824 220"
        stroke="url(#curveCool2Hot)" strokeWidth="110" strokeLinecap="round" fill="none" />
    </>
  );
}

const VARIANTS = [
  { id: 'v4', label: 'V4 · Square Plot', render: IconV4, note: 'Centered square plot, curve corner-to-corner, blue/orange endpoint dots' },
  { id: 'v0', label: 'Original', render: IconV0, note: 'Current — too busy at small sizes' },
  { id: 'v1', label: 'V1 · Hero Curve', render: IconV1, note: 'Side rail removed, curve thicker, sparser grid, 3 dots' },
  { id: 'v2', label: 'V2 · Pure Curve', render: IconV2, note: 'No chart frame; just curve + dim axis ticks' },
  { id: 'v3', label: 'V3 · Glyph', render: IconV3, note: 'One bold curve, no axes — most legible at 16px' },
  { id: 'v5', label: 'V5 · Cool→Hot Endpoints', render: IconV5, note: 'Big curve, just two endpoint dots (blue/orange)' },
  { id: 'v6', label: 'V6 · Stepped Profile', render: IconV6, note: 'Fan profile as stair-stepped curve — distinctive' },
  { id: 'v7', label: 'V7 · Minimal Mark', render: IconV7, note: 'One sweeping bezier — pure logo mark' },
];

const APPLE_ICON_SIZES = [16, 32, 64, 128, 256, 512];

function tierForSize(size) {
  if (size <= 24) return 1;
  if (size <= 48) return 2;
  if (size <= 96) return 3;
  return 4;
}

function IconAt({ render, size, rounded = true }) {
  return (
    <div style={{
      width: size, height: size, display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <svg width={size} height={size} viewBox="0 0 1024 1024" style={{ display: 'block', borderRadius: rounded ? size * 0.22 : 0 }}>
        {render({ tier: tierForSize(size) })}
      </svg>
    </div>
  );
}

function SizeLadder({ render }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-end', gap: 32, padding: '24px 32px',
      background: '#F4F4F2', borderRadius: 24,
    }}>
      {APPLE_ICON_SIZES.map((s) => (
        <div key={s} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
          <IconAt render={render} size={s} />
          <div style={{ fontSize: 11, color: '#6B6F76', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', letterSpacing: 0.4 }}>{s}px</div>
        </div>
      ))}
    </div>
  );
}

function HeroBlock({ render }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      width: 360, height: 360, background: '#EDEDEB', borderRadius: 24,
    }}>
      <IconAt render={render} size={300} />
    </div>
  );
}

function VariantCard({ v }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', gap: 18, padding: 28,
      background: '#FAFAF8', borderRadius: 28, border: '1px solid #E5E4DF',
      width: 'max-content',
    }}>
      <div style={{ display: 'flex', gap: 24, alignItems: 'center' }}>
        <HeroBlock render={v.render} />
        <div style={{ flex: 1, minWidth: 280, maxWidth: 360 }}>
          <div style={{ fontSize: 22, fontWeight: 600, color: '#15171A', letterSpacing: -0.3 }}>{v.label}</div>
          <div style={{ fontSize: 14, color: '#5C6068', marginTop: 8, lineHeight: 1.5 }}>{v.note}</div>

          {/* Dock simulation — small icon next to common macOS context */}
          <div style={{ marginTop: 22 }}>
            <div style={{ fontSize: 11, color: '#8A8E96', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', letterSpacing: 0.4, marginBottom: 8 }}>DOCK · 64px</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', background: 'rgba(255,255,255,0.6)', borderRadius: 18, backdropFilter: 'blur(8px)', border: '1px solid rgba(0,0,0,0.06)' }}>
              <div style={{ width: 60, height: 60, borderRadius: 14, background: '#D8D6CF' }} />
              <IconAt render={v.render} size={64} />
              <div style={{ width: 60, height: 60, borderRadius: 14, background: '#D8D6CF' }} />
              <div style={{ width: 60, height: 60, borderRadius: 14, background: '#D8D6CF' }} />
            </div>
          </div>

          {/* Menu-bar simulation — 16/22px */}
          <div style={{ marginTop: 18 }}>
            <div style={{ fontSize: 11, color: '#8A8E96', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', letterSpacing: 0.4, marginBottom: 8 }}>MENU BAR · 22px / FAVICON · 16px</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '8px 14px', background: '#1F1F1F', borderRadius: 10 }}>
              <IconAt render={v.render} size={22} />
              <IconAt render={v.render} size={16} />
              <div style={{ flex: 1 }} />
              <div style={{ fontSize: 11, color: '#9CA0A8', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' }}>9:41 AM</div>
            </div>
          </div>
        </div>
      </div>

      {/* Size ladder */}
      <SizeLadder render={v.render} />
    </div>
  );
}

function App() {
  return (
    <DesignCanvas
      background="#E8E7E2"
      title="FanCurve · Icon Refinement"
      subtitle="Goal: legible at 16/32/64px. Strip detail, scale up the hero curve."
    >
      <DCSection id="explore" title="Variants" subtitle="Each card: 300px hero, dock at 64, menu bar at 22, favicon at 16, plus full size ladder">
        {VARIANTS.map((v) => (
          <DCArtboard key={v.id} id={v.id} label={v.label} width={1080} height={620}>
            <VariantCard v={v} />
          </DCArtboard>
        ))}
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);

// Expose for SVG export page
Object.assign(window, { IconV4, IconV0, IconV1, IconV2, IconV3, IconV5, IconV6, IconV7, SHARED_DEFS, Tile });
