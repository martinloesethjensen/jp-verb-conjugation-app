import { useState, useMemo, useCallback, useEffect } from "react";
import type { Verb, FormKey, TeGroup } from "./types";

async function openExternal(url: string) {
  if ("__TAURI_INTERNALS__" in window) {
    const { openUrl } = await import("@tauri-apps/plugin-opener");
    await openUrl(url);
  } else {
    window.open(url, "_blank", "noopener,noreferrer");
  }
}

// ─── Static config ─────────────────────────────────────────────────────────────

const TE_GROUPS: Record<TeGroup, {
  label: string; rule: string; color: string;
  bg: { light: string; dark: string };
  border: { light: string; dark: string };
  tagBg: { light: string; dark: string };
}> = {
  tte:   { label:"って", rule:"う / つ / る → って", color:"#f97316", bg:{light:"#fff7ed",dark:"#431407"}, border:{light:"#fb923c",dark:"#c2410c"}, tagBg:{light:"#fed7aa",dark:"#7c2d12"} },
  nde:   { label:"んで", rule:"む / ぶ / ぬ → んで", color:"#2dd4bf", bg:{light:"#f0fdfa",dark:"#042f2e"}, border:{light:"#2dd4bf",dark:"#0f766e"}, tagBg:{light:"#ccfbf1",dark:"#134e4a"} },
  ite:   { label:"いて", rule:"く → いて",            color:"#a78bfa", bg:{light:"#f5f3ff",dark:"#2e1065"}, border:{light:"#a78bfa",dark:"#6d28d9"}, tagBg:{light:"#ede9fe",dark:"#3b0764"} },
  ide:   { label:"いで", rule:"ぐ → いで",            color:"#818cf8", bg:{light:"#eef2ff",dark:"#1e1b4b"}, border:{light:"#818cf8",dark:"#4338ca"}, tagBg:{light:"#e0e7ff",dark:"#1e1b4b"} },
  shite: { label:"して", rule:"す → して",            color:"#fb7185", bg:{light:"#fff1f2",dark:"#4c0519"}, border:{light:"#fb7185",dark:"#be123c"}, tagBg:{light:"#ffe4e6",dark:"#881337"} },
};

const FORM_COLS: Array<{ key: FormKey; label: string }> = [
  { key:"masu_pos",       label:"ます (polite +)" },
  { key:"masu_neg",       label:"ません (polite −)" },
  { key:"masu_past",      label:"ました (polite past +)" },
  { key:"masu_past_neg",  label:"ませんでした (polite past −)" },
  { key:"te",             label:"て-form" },
  { key:"short_pos",      label:"short (present +)" },
  { key:"short_neg",      label:"short (present −)" },
  { key:"short_past",     label:"short (past +)" },
  { key:"short_past_neg", label:"short (past −)" },
];

const TABLE_COLS: Array<{ key: FormKey; label: string }> = [
  { key:"masu_pos",       label:"ます\n(polite +)" },
  { key:"masu_neg",       label:"ません\n(polite −)" },
  { key:"masu_past",      label:"ました\n(polite past +)" },
  { key:"masu_past_neg",  label:"ませんでした\n(polite past −)" },
  { key:"te",             label:"て-form" },
  { key:"short_pos",      label:"short\n(present +)" },
  { key:"short_neg",      label:"short\n(present −)" },
  { key:"short_past",     label:"short\n(past +)" },
  { key:"short_past_neg", label:"short\n(past −)" },
];

// ─── Quiz logic ────────────────────────────────────────────────────────────────

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

interface Question {
  verb: Verb;
  form: FormKey;
  correct: string;
  choices: string[];
}

function buildQuestions(verbs: Verb[], count: number): Question[] {
  const allForms = FORM_COLS.map(f => f.key);
  const pool: { verb: Verb; form: FormKey; correct: string }[] = [];
  verbs.forEach(v => allForms.forEach(f => pool.push({ verb: v, form: f, correct: v.forms[f] })));
  const shuffledPool = shuffle(pool).slice(0, count);

  return shuffledPool.map(({ verb, form, correct }) => {
    const wrongSameVerb = allForms
      .filter(f => f !== form)
      .map(f => verb.forms[f])
      .filter(v => v !== correct);
    const wrongOtherVerbs = verbs
      .filter(v2 => v2.dict !== verb.dict)
      .map(v2 => v2.forms[form])
      .filter(v => v !== correct);
    const wrongs = shuffle([...wrongSameVerb, ...wrongOtherVerbs]);
    const distractors = [...new Set(wrongs)].slice(0, 3);
    const choices = shuffle([correct, ...distractors]);
    return { verb, form, correct, choices };
  });
}

// ─── Quiz Screen ───────────────────────────────────────────────────────────────

const KAHOOT_COLORS = ["#e21b3c", "#1368ce", "#d89e00", "#26890c"];
const KAHOOT_SHAPES = ["▲", "◆", "●", "■"];

interface QuizResult {
  verb: string;
  form: FormKey;
  correct: string;
  chosen: string;
  ok: boolean;
}

function QuizScreen({ questions, dark, onDone }: { questions: Question[]; dark: boolean; onDone: () => void }) {
  const [idx, setIdx] = useState(0);
  const [selected, setSelected] = useState<string | null>(null);
  const [score, setScore] = useState(0);
  const [results, setResults] = useState<QuizResult[]>([]);
  const [finished, setFinished] = useState(false);
  const [timeLeft, setTimeLeft] = useState(20);
  const [timedOut, setTimedOut] = useState(false);

  const q = questions[idx];
  const formLabel = FORM_COLS.find(c => c.key === q?.form)?.label ?? "";
  const answered = selected !== null || timedOut;

  useEffect(() => {
    if (answered) return;
    setTimeLeft(20);
    const iv = setInterval(() => {
      setTimeLeft(t => {
        if (t <= 1) { clearInterval(iv); setTimedOut(true); return 0; }
        return t - 1;
      });
    }, 1000);
    return () => clearInterval(iv);
  }, [idx, answered]);

  const choose = (choice: string) => {
    if (answered) return;
    setSelected(choice);
    const isCorrect = choice === q.correct;
    if (isCorrect) setScore(s => s + 1);
    setResults(r => [...r, { verb: q.verb.dict, form: q.form, correct: q.correct, chosen: choice, ok: isCorrect }]);
  };

  const next = () => {
    if (idx + 1 >= questions.length) { setFinished(true); }
    else { setSelected(null); setTimedOut(false); setIdx(i => i + 1); }
  };

  const surf = dark ? "#1c1917" : "#fff";
  const bdr = dark ? "#44403c" : "#e7e5e4";
  const txt = dark ? "#fafaf9" : "#1c1917";
  const sub = dark ? "#a8a29e" : "#78716c";

  if (finished) {
    const pct = Math.round((score / questions.length) * 100);
    const emoji = pct === 100 ? "🏆" : pct >= 80 ? "🌟" : pct >= 60 ? "👍" : pct >= 40 ? "📚" : "💪";
    return (
      <div style={{display:"flex",flexDirection:"column",alignItems:"center",padding:"40px 24px",gap:20,minHeight:"100vh",background:dark?"#0c0a09":"#f0f9ff"}}>
        <div style={{fontSize:56}}>{emoji}</div>
        <h2 style={{fontSize:28,fontWeight:800,color:txt}}>Quiz Complete!</h2>
        <div style={{fontSize:48,fontWeight:900,color:pct>=60?"#22c55e":"#f97316"}}>{score}/{questions.length}</div>
        <div style={{fontSize:16,color:sub}}>{pct}% correct</div>
        <div style={{width:"100%",maxWidth:480,background:surf,borderRadius:16,overflow:"hidden",border:`1px solid ${bdr}`}}>
          {results.map((r, i) => {
            const fl = FORM_COLS.find(c => c.key === r.form)?.label ?? r.form;
            return (
              <div key={i} style={{padding:"12px 16px",borderBottom:`1px solid ${bdr}`,display:"flex",gap:12,alignItems:"flex-start"}}>
                <span style={{fontSize:18,marginTop:2}}>{r.ok ? "✅" : "❌"}</span>
                <div>
                  <div style={{fontSize:13,fontWeight:600,color:txt}}>{r.verb} — {fl}</div>
                  {!r.ok && <div style={{fontSize:12,color:"#ef4444"}}>You chose: {r.chosen}</div>}
                  <div style={{fontSize:12,color:"#22c55e"}}>Correct: {r.correct}</div>
                </div>
              </div>
            );
          })}
        </div>
        <button onClick={onDone} style={{padding:"14px 32px",borderRadius:12,background:"#7c3aed",color:"#fff",fontWeight:700,fontSize:16,border:"none",cursor:"pointer"}}>
          Back to Table
        </button>
      </div>
    );
  }

  const timerPct = (timeLeft / 20) * 100;
  const timerColor = timeLeft > 10 ? "#22c55e" : timeLeft > 5 ? "#f59e0b" : "#ef4444";

  return (
    <div style={{minHeight:"100vh",background:dark?"#0c0a09":"#1a1a2e",display:"flex",flexDirection:"column"}}>
      <div style={{background:"#7c3aed",padding:"12px 20px",display:"flex",alignItems:"center",justifyContent:"space-between"}}>
        <span style={{color:"#fff",fontWeight:700,fontSize:14}}>{idx + 1} / {questions.length}</span>
        <div style={{display:"flex",gap:8,alignItems:"center"}}>
          <span style={{color:"#fff",fontSize:13,fontWeight:600}}>⭐ {score}</span>
          <button onClick={onDone} style={{background:"rgba(255,255,255,0.2)",border:"none",borderRadius:8,color:"#fff",fontSize:13,padding:"4px 10px",cursor:"pointer"}}>✕</button>
        </div>
      </div>
      <div style={{height:6,background:dark?"#292524":"#2d2d44"}}>
        <div style={{height:"100%",width:`${timerPct}%`,background:timerColor,transition:"width 1s linear"}}/>
      </div>
      <div style={{flex:1,display:"flex",flexDirection:"column",alignItems:"center",padding:"24px 16px 16px",gap:20}}>
        <div style={{background:surf,borderRadius:20,padding:"24px 28px",maxWidth:520,width:"100%",textAlign:"center",boxShadow:"0 8px 32px rgba(0,0,0,0.3)"}}>
          <div style={{fontSize:12,color:sub,fontWeight:700,textTransform:"uppercase",letterSpacing:"0.06em",marginBottom:8}}>
            What is the <b style={{color:"#7c3aed"}}>{formLabel}</b> form of…
          </div>
          <div style={{fontSize:42,fontWeight:900,color:txt,letterSpacing:"-0.02em"}}>{q.verb.dict}</div>
          {q.verb.kanji && <div style={{fontSize:20,color:sub,marginTop:2}}>{q.verb.kanji}</div>}
          <div style={{fontSize:14,color:sub,marginTop:4,fontStyle:"italic"}}>{q.verb.meaning}</div>
          <div style={{marginTop:12,display:"flex",alignItems:"center",justifyContent:"center",gap:6}}>
            <div style={{fontSize:20,fontWeight:700,color:timerColor}}>⏱ {timeLeft}s</div>
          </div>
        </div>
        <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:12,width:"100%",maxWidth:520}}>
          {q.choices.map((choice, ci) => {
            const isCorrect = choice === q.correct;
            const isSelected = choice === selected;
            let bg = KAHOOT_COLORS[ci];
            let opacity = 1;
            if (answered) {
              if (isCorrect) bg = "#22c55e";
              else if (isSelected && !isCorrect) bg = "#ef4444";
              else opacity = 0.35;
            }
            return (
              <button key={ci} onClick={() => choose(choice)} disabled={answered}
                style={{
                  background:bg, opacity, color:"#fff", border:"none", borderRadius:14,
                  padding:"18px 12px", cursor:answered?"default":"pointer",
                  fontWeight:700, fontSize:17, fontFamily:"inherit",
                  display:"flex", alignItems:"center", gap:10, justifyContent:"center",
                  boxShadow:"0 4px 12px rgba(0,0,0,0.3)",
                  transform: isSelected && answered && !isCorrect ? "scale(0.97)" : "scale(1)",
                  transition:"opacity 0.3s, transform 0.15s", minHeight:72,
                }}>
                <span style={{fontSize:20}}>{KAHOOT_SHAPES[ci]}</span>
                <span style={{wordBreak:"break-all"}}>{choice}</span>
                {answered && isCorrect && <span>✓</span>}
                {answered && isSelected && !isCorrect && <span>✗</span>}
              </button>
            );
          })}
        </div>
        {answered && (
          <div style={{display:"flex",flexDirection:"column",alignItems:"center",gap:12,width:"100%",maxWidth:520}}>
            <div style={{
              background: timedOut ? "#f59e0b" : selected === q.correct ? "#22c55e" : "#ef4444",
              color:"#fff", borderRadius:12, padding:"12px 20px", textAlign:"center", width:"100%", fontWeight:700, fontSize:16,
            }}>
              {timedOut ? "⏰ Time's up!" : selected === q.correct ? "🎉 Correct!" : `❌ The answer was: ${q.correct}`}
            </div>
            <button onClick={next} style={{padding:"13px 40px",borderRadius:12,background:"#7c3aed",color:"#fff",fontWeight:700,fontSize:16,border:"none",cursor:"pointer",boxShadow:"0 4px 12px rgba(124,58,237,0.4)"}}>
              {idx + 1 >= questions.length ? "See Results →" : "Next →"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Settings Modal ────────────────────────────────────────────────────────────

interface Settings { count: number }

function SettingsModal({ settings, onSave, onClose, dark }: { settings: Settings; onSave: (s: Settings) => void; onClose: () => void; dark: boolean }) {
  const [count, setCount] = useState(settings.count);
  const surf = dark ? "#1c1917" : "#fff";
  const bdr = dark ? "#44403c" : "#e7e5e4";
  const txt = dark ? "#fafaf9" : "#1c1917";
  const sub = dark ? "#a8a29e" : "#78716c";
  const options = [5, 10, 15, 20, 30];
  return (
    <div style={{position:"fixed",inset:0,background:"rgba(0,0,0,0.5)",zIndex:300,display:"flex",alignItems:"center",justifyContent:"center",padding:16}} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{background:surf,borderRadius:20,padding:"28px 24px",maxWidth:380,width:"100%",boxShadow:"0 24px 48px rgba(0,0,0,0.3)"}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:20}}>
          <h2 style={{fontSize:20,fontWeight:700,color:txt}}>⚙️ Quiz Settings</h2>
          <button onClick={onClose} style={{background:"none",border:"none",fontSize:20,cursor:"pointer",color:sub}}>✕</button>
        </div>
        <div style={{marginBottom:20}}>
          <div style={{fontSize:13,fontWeight:700,color:sub,textTransform:"uppercase",letterSpacing:"0.05em",marginBottom:12}}>Number of questions</div>
          <div style={{display:"flex",gap:8,flexWrap:"wrap"}}>
            {options.map(n => (
              <button key={n} onClick={() => setCount(n)} style={{
                padding:"8px 18px", borderRadius:9999, border:`2px solid ${count === n ? "#7c3aed" : bdr}`,
                background: count === n ? "#7c3aed" : "transparent", color: count === n ? "#fff" : txt,
                fontWeight:700, fontSize:14, cursor:"pointer", transition:"all 0.15s",
              }}>{n}</button>
            ))}
          </div>
        </div>
        <button onClick={() => { onSave({ count }); onClose(); }} style={{width:"100%",padding:"13px",borderRadius:12,background:"#7c3aed",color:"#fff",fontWeight:700,fontSize:15,border:"none",cursor:"pointer"}}>
          Save Settings
        </button>
      </div>
    </div>
  );
}

// ─── Helper renderers ──────────────────────────────────────────────────────────

function getTypeColors(dark: boolean) {
  return {
    "irr.": { border:dark?"#f87171":"#f97066", tag:dark?"#fca5a5":"#b42318", tagBg:dark?"#450a0a":"#fee4e2" },
    "ru":   { border:dark?"#38bdf8":"#7cd4fd", tag:dark?"#7dd3fc":"#026aa2", tagBg:dark?"#0c4a6e":"#e0f2fe" },
    "u":    { border:dark?"#facc15":"#fde272", tag:dark?"#fde047":"#854d0e", tagBg:dark?"#422006":"#fef9c3" },
  };
}

function matchesSearch(v: Verb, q: string): boolean {
  if (!q) return true;
  const lq = q.toLowerCase();
  if (v.dict.includes(q)) return true;
  if (v.kanji && v.kanji.includes(q)) return true;
  if (v.meaning.toLowerCase().includes(lq)) return true;
  for (const val of Object.values(v.forms)) if (val.includes(q)) return true;
  return false;
}

// ─── Detail Modal ──────────────────────────────────────────────────────────────

function DetailModal({ verb, dark, onClose, onExamples, onQuiz }: {
  verb: Verb; dark: boolean; onClose: () => void; onExamples: () => void; onQuiz: () => void;
}) {
  const surf = dark ? "#1c1917" : "#fff";
  const surf2 = dark ? "#292524" : "#f5f5f4";
  const bdr = dark ? "#44403c" : "#e7e5e4";
  const txt = dark ? "#fafaf9" : "#1c1917";
  const sub = dark ? "#a8a29e" : "#78716c";
  const muted = dark ? "#78716c" : "#a8a29e";
  const TC = getTypeColors(dark);
  const tg = verb.teGroup ? TE_GROUPS[verb.teGroup] : null;
  const tc = TC[verb.type];
  const accent = tg ? tg.color : (dark ? "#7dd3fc" : "#0284c7");

  return (
    <div style={{position:"fixed",inset:0,background:dark?"rgba(0,0,0,0.65)":"rgba(0,0,0,0.45)",zIndex:200,display:"flex",alignItems:"center",justifyContent:"center",padding:16}} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{background:surf,borderRadius:20,width:"100%",maxWidth:560,maxHeight:"88vh",overflowY:"auto",boxShadow:`0 32px 64px rgba(0,0,0,${dark?0.6:0.18})`}}>
        <div style={{background:tg?tg.bg[dark?"dark":"light"]:(dark?"#1e293b":"#f0f9ff"),borderRadius:"20px 20px 0 0",padding:"24px 24px 20px",borderBottom:`1px solid ${bdr}`,position:"relative"}}>
          <button onClick={onClose} style={{position:"absolute",top:16,right:16,background:dark?"rgba(255,255,255,0.08)":"rgba(0,0,0,0.06)",border:"none",borderRadius:"50%",width:32,height:32,cursor:"pointer",color:sub,fontSize:16,display:"flex",alignItems:"center",justifyContent:"center"}}>✕</button>
          <div style={{display:"flex",gap:8,marginBottom:12,flexWrap:"wrap"}}>
            <span style={{background:tg?tg.tagBg[dark?"dark":"light"]:tc.tagBg,color:tg?tg.color:tc.tag,padding:"3px 10px",borderRadius:9999,fontSize:12,fontWeight:700}}>{verb.label}{tg ? ` · ${tg.label}` : ""}</span>
            {tg && <span style={{fontSize:12,color:tg.color,fontWeight:600,background:tg.tagBg[dark?"dark":"light"],padding:"3px 10px",borderRadius:9999,border:`1.5px solid ${tg.border[dark?"dark":"light"]}`}}>{tg.rule}</span>}
          </div>
          <div style={{display:"flex",alignItems:"baseline",gap:12,flexWrap:"wrap"}}>
            <span style={{fontSize:40,fontWeight:800,color:accent}}>{verb.dict}</span>
            {verb.kanji && <span style={{fontSize:26,color:sub,fontWeight:500}}>{verb.kanji}</span>}
          </div>
          <div style={{fontSize:16,color:sub,marginTop:4,fontStyle:"italic"}}>{verb.meaning}</div>
        </div>
        <div style={{padding:"20px 24px",display:"flex",flexDirection:"column",gap:18}}>
          <div>
            <div style={{fontSize:11,fontWeight:700,color:muted,textTransform:"uppercase",letterSpacing:"0.06em",marginBottom:6}}>About this verb</div>
            <p style={{fontSize:14,lineHeight:1.75,color:txt}}>{verb.description}</p>
          </div>
          {verb.notes && (
            <div style={{background:surf2,border:`1px solid ${bdr}`,borderRadius:10,padding:"12px 14px",display:"flex",gap:10}}>
              <span style={{fontSize:18,flexShrink:0}}>💡</span>
              <p style={{fontSize:13,lineHeight:1.7,color:sub}}>{verb.notes}</p>
            </div>
          )}
          <div>
            <div style={{fontSize:11,fontWeight:700,color:muted,textTransform:"uppercase",letterSpacing:"0.06em",marginBottom:8}}>Key forms</div>
            <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:8}}>
              {([["Dictionary", verb.forms.short_pos], ["て-form", verb.forms.te], ["Polite +", verb.forms.masu_pos], ["Polite −", verb.forms.masu_neg], ["Past (polite)", verb.forms.masu_past], ["Short neg.", verb.forms.short_neg]] as [string, string][]).map(([label, val]) => (
                <div key={label} style={{background:surf2,borderRadius:8,padding:"8px 12px"}}>
                  <div style={{fontSize:10,color:muted,fontWeight:600,textTransform:"uppercase",letterSpacing:"0.04em",marginBottom:2}}>{label}</div>
                  <div style={{fontSize:16,fontWeight:600,color:accent}}>{val}</div>
                </div>
              ))}
            </div>
          </div>
          <div style={{display:"flex",gap:10,flexWrap:"wrap"}}>
            <button onClick={onExamples} style={{flex:1,minWidth:120,padding:"11px 14px",borderRadius:10,border:`1.5px solid ${accent}`,background:"transparent",color:accent,fontWeight:600,fontSize:13,cursor:"pointer",fontFamily:"inherit"}}
              onMouseEnter={e => { e.currentTarget.style.background = accent; e.currentTarget.style.color = dark ? "#0c0a09" : "#fff"; }}
              onMouseLeave={e => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = accent; }}>
              📖 Examples
            </button>
            <button onClick={onQuiz} style={{flex:1,minWidth:120,padding:"11px 14px",borderRadius:10,background:"#7c3aed",color:"#fff",fontWeight:600,fontSize:13,cursor:"pointer",fontFamily:"inherit",border:"none",boxShadow:"0 4px 12px rgba(124,58,237,0.35)"}}>
              🎮 Test this verb
            </button>
            <button onClick={() => openExternal(`https://jisho.org/search/${encodeURIComponent(verb.dict)}`)}
              style={{flex:1,minWidth:120,padding:"11px 14px",borderRadius:10,background:"#22c55e",color:"#fff",fontWeight:600,fontSize:13,fontFamily:"inherit",border:"none",cursor:"pointer",display:"flex",alignItems:"center",justifyContent:"center",gap:5}}>
              🔗 Jisho
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Examples Modal ────────────────────────────────────────────────────────────

function ExamplesModal({ verb, dark, onClose, onBack }: {
  verb: Verb; dark: boolean; onClose: () => void; onBack: () => void;
}) {
  const surf = dark ? "#1c1917" : "#fff";
  const bdr = dark ? "#44403c" : "#e7e5e4";
  const txt = dark ? "#fafaf9" : "#1c1917";
  const sub = dark ? "#a8a29e" : "#78716c";
  const muted = dark ? "#78716c" : "#a8a29e";
  const tg = verb.teGroup ? TE_GROUPS[verb.teGroup] : null;
  const accent = tg ? tg.color : (dark ? "#7dd3fc" : "#0284c7");

  return (
    <div style={{position:"fixed",inset:0,background:dark?"rgba(0,0,0,0.65)":"rgba(0,0,0,0.45)",zIndex:200,display:"flex",alignItems:"center",justifyContent:"center",padding:16}} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{background:surf,borderRadius:20,width:"100%",maxWidth:520,maxHeight:"88vh",overflowY:"auto",boxShadow:`0 32px 64px rgba(0,0,0,${dark?0.6:0.18})`}}>
        <div style={{position:"sticky",top:0,background:surf,borderBottom:`1px solid ${bdr}`,padding:"14px 20px",zIndex:1,borderRadius:"20px 20px 0 0"}}>
          <div style={{display:"flex",alignItems:"center",gap:10}}>
            <button onClick={onBack} style={{background:"none",border:"none",cursor:"pointer",color:sub,fontSize:20,padding:0}}>←</button>
            <span style={{fontSize:22,fontWeight:700,color:accent}}>{verb.dict}</span>
            {verb.kanji && <span style={{fontSize:15,color:sub,marginLeft:4}}>{verb.kanji}</span>}
            <button onClick={onClose} style={{marginLeft:"auto",background:"none",border:"none",cursor:"pointer",color:sub,fontSize:20,padding:0}}>✕</button>
          </div>
        </div>
        <div style={{padding:"0 20px 24px"}}>
          {(verb.examples ?? []).map((ex, i) => {
            const fl = FORM_COLS.find(c => c.key === ex.form)?.label ?? ex.form;
            return (
              <div key={i} style={{padding:"13px 0",borderBottom:`1px solid ${bdr}`}}>
                <div style={{fontSize:10,fontWeight:700,color:muted,textTransform:"uppercase",letterSpacing:"0.06em",marginBottom:4}}>{fl}</div>
                <div style={{fontSize:18,fontWeight:500,lineHeight:1.6,color:txt}}>{ex.jp}</div>
                <div style={{fontSize:13,color:sub,marginTop:2}}>{ex.en}</div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ─── Main App ──────────────────────────────────────────────────────────────────

export default function App() {
  const [dark, setDark] = useState(false);
  const [verbData, setVerbData] = useState<Verb[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [detail, setDetail] = useState<Verb | null>(null);
  const [examples, setExamples] = useState<Verb | null>(null);
  const [filter, setFilter] = useState("all");
  const [showGuide, setShowGuide] = useState(false);
  const [search, setSearch] = useState("");
  const [quizQuestions, setQuizQuestions] = useState<Question[] | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [settings, setSettings] = useState<Settings>({ count: 10 });

  useEffect(() => {
    fetch("/verbs.json")
      .then(r => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
      .then(data => { setVerbData(data.verbs); setLoading(false); })
      .catch(() => { setLoadError("Failed to load verb data."); setLoading(false); });
  }, []);

  const filtered = useMemo(() =>
    verbData.filter(v => (filter === "all" || v.type === filter) && matchesSearch(v, search.trim())),
    [verbData, filter, search]
  );

  const startQuizAll = useCallback(() => {
    setQuizQuestions(buildQuestions(verbData, settings.count));
  }, [verbData, settings.count]);

  const startQuizVerb = useCallback((verb: Verb) => {
    setDetail(null);
    setQuizQuestions(buildQuestions([verb], Math.min(settings.count, 9)));
  }, [settings.count]);

  const TYPE_COLORS = getTypeColors(dark);
  const bg = dark ? "#0c0a09" : "#fafaf9";
  const surf = dark ? "#1c1917" : "#fff";
  const surf2 = dark ? "#292524" : "#f5f5f4";
  const bdr = dark ? "#44403c" : "#e7e5e4";
  const txt = dark ? "#fafaf9" : "#1c1917";
  const sub = dark ? "#a8a29e" : "#78716c";
  const muted = dark ? "#78716c" : "#a8a29e";
  const pillBase: React.CSSProperties = {cursor:"pointer",border:`1.5px solid ${bdr}`,background:surf,borderRadius:9999,padding:"6px 16px",fontSize:13,fontWeight:500,color:txt};
  const pillActive: React.CSSProperties = {...pillBase,background:dark?"#fafaf9":"#292524",color:dark?"#1c1917":"#fafaf9",borderColor:dark?"#fafaf9":"#292524"};

  if (quizQuestions) {
    return <QuizScreen questions={quizQuestions} dark={dark} onDone={() => setQuizQuestions(null)} />;
  }

  return (
    <div style={{fontFamily:"'Noto Sans JP','Hiragino Sans',sans-serif",background:bg,minHeight:"100vh",color:txt,transition:"background 0.2s,color 0.2s"}}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@300;400;500;700&display=swap');
        *{box-sizing:border-box;margin:0;padding:0;}
        .fade-in{animation:fadeIn 0.25s ease;}
        @keyframes fadeIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}
        .hover-row:hover{filter:brightness(${dark ? "1.15" : "0.97"});}
        .tag{display:inline-block;padding:2px 8px;border-radius:9999px;font-size:11px;font-weight:600;letter-spacing:0.02em;}
        table{width:100%;border-collapse:collapse;}
        th,td{padding:10px 12px;text-align:left;border-bottom:1px solid ${bdr};font-size:14px;white-space:pre-line;}
        th{background:${surf2};font-weight:600;font-size:12px;color:${sub};text-transform:uppercase;letter-spacing:0.04em;position:sticky;top:0;z-index:2;}
        .dict-cell{font-weight:700;font-size:16px;cursor:pointer;}
        .dict-cell:hover{opacity:0.7;}
        .meaning{font-size:11px;color:${muted};font-weight:400;display:block;}
        .tap-hint{font-size:10px;color:${muted};font-weight:400;display:block;margin-top:1px;}
        .toggle-track{width:44px;height:24px;border-radius:9999px;background:${dark?"#7c3aed":"#d6d3d1"};cursor:pointer;position:relative;transition:background 0.2s;border:none;flex-shrink:0;}
        .toggle-thumb{position:absolute;top:3px;left:${dark?"21px":"3px"};width:18px;height:18px;border-radius:50%;background:#fff;transition:left 0.2s;box-shadow:0 1px 4px rgba(0,0,0,0.3);}
        .search-input{width:100%;padding:9px 14px 9px 38px;border-radius:10px;border:1.5px solid ${bdr};background:${surf2};color:${txt};font-size:14px;font-family:inherit;outline:none;transition:border 0.15s;}
        .search-input:focus{border-color:${dark?"#a78bfa":"#7c3aed"};}
        .search-input::placeholder{color:${muted};}
        .search-wrap{position:relative;flex:1;min-width:180px;}
        .search-icon{position:absolute;left:11px;top:50%;transform:translateY(-50%);color:${muted};pointer-events:none;font-size:15px;}
        .clear-btn{position:absolute;right:10px;top:50%;transform:translateY(-50%);background:none;border:none;cursor:pointer;color:${muted};font-size:16px;line-height:1;padding:0;}
        .quiz-btn{background:linear-gradient(135deg,#7c3aed,#a855f7);color:#fff;border:none;border-radius:10px;padding:9px 18px;font-weight:700;font-size:13px;cursor:pointer;font-family:inherit;box-shadow:0 4px 12px rgba(124,58,237,0.35);transition:transform 0.1s;}
        .quiz-btn:hover{transform:translateY(-1px);}
        .settings-btn{background:${surf2};color:${txt};border:1.5px solid ${bdr};border-radius:10px;padding:9px 14px;font-weight:600;font-size:13px;cursor:pointer;font-family:inherit;}
      `}</style>

      {/* Header */}
      <div style={{padding:"24px 24px 16px",borderBottom:`1px solid ${bdr}`,background:surf}}>
        <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",flexWrap:"wrap",gap:10}}>
          <div style={{display:"flex",alignItems:"baseline",gap:10,flexWrap:"wrap"}}>
            <h1 style={{fontSize:24,fontWeight:700,letterSpacing:"-0.02em"}}>動詞活用表</h1>
            <span style={{fontSize:13,color:sub}}>Japanese Verb Conjugations</span>
          </div>
          <div style={{display:"flex",alignItems:"center",gap:8}}>
            <span style={{fontSize:13,color:sub}}>{dark ? "🌙" : "☀️"}</span>
            <button className="toggle-track" onClick={() => setDark(!dark)}><div className="toggle-thumb"/></button>
          </div>
        </div>

        <div style={{display:"flex",gap:8,marginTop:14,alignItems:"center",flexWrap:"wrap"}}>
          <button className="quiz-btn" onClick={startQuizAll} disabled={loading}>🎮 Random Quiz ({settings.count}Q)</button>
          <button className="settings-btn" onClick={() => setShowSettings(true)}>⚙️ {settings.count} questions</button>
        </div>

        <div style={{display:"flex",gap:8,marginTop:10,flexWrap:"wrap",alignItems:"center"}}>
          <div className="search-wrap">
            <span className="search-icon">🔍</span>
            <input className="search-input" placeholder="Search hiragana, kanji, or English…" value={search} onChange={e => setSearch(e.target.value)} spellCheck={false}/>
            {search && <button className="clear-btn" onClick={() => setSearch("")}>✕</button>}
          </div>
        </div>
        <div style={{display:"flex",gap:8,marginTop:10,flexWrap:"wrap",alignItems:"center"}}>
          {(([["all","All"],["irr.","Irregular"],["ru","Ru-verbs"],["u","U-verbs"]] as [string, string][])).map(([k, l]) => (
            <button key={k} style={filter === k ? pillActive : pillBase} onClick={() => setFilter(k)}>{l}</button>
          ))}
          <div style={{flex:1}}/>
          <button style={showGuide ? pillActive : pillBase} onClick={() => setShowGuide(!showGuide)}>{showGuide ? "Hide guide" : "Verb type guide"}</button>
        </div>
        {(search || filter !== "all") && !loading && (
          <p style={{fontSize:12,color:muted,marginTop:8}}>
            {filtered.length === 0 ? "No verbs found." : `Showing ${filtered.length} of ${verbData.length} verbs`}
            {search && <> matching <b style={{color:txt}}>"{search}"</b></>}
          </p>
        )}
      </div>

      {showGuide && (
        <div className="fade-in" style={{padding:"20px 24px",background:dark?"#1a180f":"#fefce8",borderBottom:`1px solid ${dark?"#713f12":"#fde68a"}`}}>
          <h2 style={{fontSize:18,fontWeight:700,marginBottom:14}}>How to identify verb types</h2>
          {[
            { tag:"Ru-verb (一段)", tagBg:dark?"#0c4a6e":"#e0f2fe", tagColor:dark?"#7dd3fc":"#026aa2", body:<>Ends in <b>-eru</b> or <b>-iru</b>. Drop the final <b>る</b> and add the ending.<br/><span style={{color:sub,fontSize:13}}>⚠ Exceptions: はいる, かえる, きる "to cut" look like ru-verbs but are u-verbs.</span></> },
            { tag:"U-verb (五段)", tagBg:dark?"#422006":"#fef9c3", tagColor:dark?"#fde047":"#854d0e", body:<>Ends in any <b>-u</b> sound. If not -eru/-iru, it's definitely a u-verb.</> },
            { tag:"Irregular", tagBg:dark?"#450a0a":"#fee4e2", tagColor:dark?"#fca5a5":"#b42318", body:<>Only <b>する</b> and <b>くる</b>. Compounds like べんきょうする follow する.</> },
          ].map((g, i) => (
            <div key={i} style={{background:surf,border:`1px solid ${bdr}`,borderRadius:12,padding:"14px 18px",marginBottom:10}}>
              <span className="tag" style={{background:g.tagBg,color:g.tagColor}}>{g.tag}</span>
              <p style={{fontSize:14,lineHeight:1.7,marginTop:8}}>{g.body}</p>
            </div>
          ))}
        </div>
      )}

      {/* て-form legend */}
      <div style={{padding:"8px 24px",background:surf,borderBottom:`1px solid ${bdr}`,display:"flex",gap:8,flexWrap:"wrap",alignItems:"center"}}>
        <span style={{fontSize:11,color:sub,fontWeight:600,marginRight:4}}>て-form:</span>
        {Object.entries(TE_GROUPS).map(([k, g]) => (
          <span key={k} style={{display:"inline-flex",alignItems:"center",gap:4,fontSize:11,color:g.color,fontWeight:600,background:g.tagBg[dark?"dark":"light"],padding:"3px 10px",borderRadius:9999,border:`1.5px solid ${g.border[dark?"dark":"light"]}`}}>{g.rule}</span>
        ))}
      </div>

      {/* Table */}
      <div style={{overflowX:"auto"}}>
        {loading ? (
          <div style={{padding:"64px 24px",textAlign:"center",color:muted}}>
            <div style={{fontSize:32,marginBottom:12}}>⏳</div>
            <div style={{fontSize:15,color:sub}}>Loading verb data…</div>
          </div>
        ) : loadError ? (
          <div style={{padding:"64px 24px",textAlign:"center",color:muted}}>
            <div style={{fontSize:32,marginBottom:12}}>⚠️</div>
            <div style={{fontSize:15,color:"#ef4444"}}>{loadError}</div>
          </div>
        ) : filtered.length === 0 ? (
          <div style={{padding:"48px 24px",textAlign:"center",color:muted}}>
            <div style={{fontSize:36,marginBottom:12}}>🔍</div>
            <div style={{fontSize:16,fontWeight:600,color:sub}}>No verbs found</div>
          </div>
        ) : (
          <table>
            <thead>
              <tr>
                <th style={{minWidth:50}}>Type</th>
                <th style={{minWidth:90}}>Verb</th>
                {TABLE_COLS.map(c => <th key={c.key} style={{minWidth:90}}>{c.label}</th>)}
              </tr>
            </thead>
            <tbody>
              {(() => {
                let prevTeGroup: string | null = null;
                return filtered.flatMap((v, i) => {
                  const tc = TYPE_COLORS[v.type];
                  const tg = v.teGroup ? TE_GROUPS[v.teGroup] : null;
                  const borderColor = tg ? tg.border[dark?"dark":"light"] : tc.border;
                  const rows: React.ReactNode[] = [];
                  if (!search && v.teGroup && v.teGroup !== prevTeGroup) {
                    rows.push(
                      <tr key={`sep-${v.teGroup}-${i}`} style={{background:tg!.bg[dark?"dark":"light"]}}>
                        <td colSpan={2 + TABLE_COLS.length} style={{borderLeft:`3px solid ${tg!.border[dark?"dark":"light"]}`,color:tg!.color,padding:"5px 12px",fontSize:12,fontWeight:700,borderBottom:`1px solid ${bdr}`}}>{tg!.rule}</td>
                      </tr>
                    );
                  }
                  prevTeGroup = v.teGroup ?? prevTeGroup;
                  rows.push(
                    <tr key={i} className="hover-row" style={{background:i%2===0?surf:surf2,borderLeft:`3px solid ${borderColor}`}}>
                      <td><span className="tag" style={{background:tg?tg.tagBg[dark?"dark":"light"]:tc.tagBg,color:tg?tg.color:tc.tag}}>{v.type}</span></td>
                      <td className="dict-cell" style={{color:tg?tg.color:txt}} onClick={() => setDetail(v)}>
                        {v.dict}
                        {v.kanji && <span style={{fontSize:12,color:sub,fontWeight:500,display:"block"}}>{v.kanji}</span>}
                        <span className="meaning">{v.meaning}</span>
                        <span className="tap-hint">Tap for details →</span>
                      </td>
                      {TABLE_COLS.map(c => <td key={c.key}>{v.forms[c.key] ?? "—"}</td>)}
                    </tr>
                  );
                  return rows;
                });
              })()}
            </tbody>
          </table>
        )}
      </div>

      <div style={{padding:"14px 24px",fontSize:12,color:muted}}>
        Tap any verb name for details. <b>🎮 Random Quiz</b> tests conjugations from all verbs.
        {" · "}
        <button onClick={() => openExternal("https://github.com/martinj/jp-verb-conjugation-app/issues/new?template=add-verb.yml")}
          style={{background:"none",border:"none",color:"#7c3aed",cursor:"pointer",fontSize:"inherit",padding:0,fontFamily:"inherit"}}>
          Suggest a verb
        </button>
      </div>

      {detail && !examples && (
        <DetailModal verb={detail} dark={dark} onClose={() => setDetail(null)} onExamples={() => setExamples(detail)} onQuiz={() => startQuizVerb(detail)}/>
      )}
      {examples && (
        <ExamplesModal verb={examples} dark={dark} onClose={() => { setExamples(null); setDetail(null); }} onBack={() => setExamples(null)}/>
      )}
      {showSettings && (
        <SettingsModal settings={settings} onSave={s => setSettings(s)} onClose={() => setShowSettings(false)} dark={dark}/>
      )}
    </div>
  );
}
