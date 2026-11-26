(() => {
    "use strict";
    const canvas = document.getElementById("canvas");
    const issueUrl = document.querySelector('meta[name="review-issues"]')?.content;
    const feedbackOnly = document.querySelector('meta[name="review-mode"]')?.content === "feedback";
    const issuePage = issueUrl ? new URL(issueUrl) : null;
    const repository = issuePage?.origin === "https://github.com"
        ? /^\/([\w.-]+\/[\w.-]+)\/issues\/new\/?$/.exec(issuePage.pathname)?.[1]
        : null;
    if (!issueUrl) {
        const getContext = canvas.getContext.bind(canvas);
        canvas.getContext = (name, options) => getContext(name, name.startsWith("webgl")
            ? { ...options, preserveDrawingBuffer: true }
            : options);
    }

    const style = document.createElement("style");
    style.textContent = `
        #suqi-review { position: fixed; z-index: 200; top: max(12px, env(safe-area-inset-top));
          left: max(12px, env(safe-area-inset-left)); width: max-content; max-width: calc(100vw - 24px);
          color: #fff6e6; font: 14px/1.45 system-ui, sans-serif; text-align: left; touch-action: manipulation; }
        #suqi-review button, #suqi-review select, #suqi-note button { font: inherit; border-radius: 7px;
          border: 1px solid #bca182; padding: 8px 10px; color: #fff6e6; background: #352822; cursor: pointer; }
        #suqi-review button[aria-pressed="true"], #suqi-note button[type="submit"] { background: #85424a; }
        #suqi-review button:disabled, #suqi-review select:disabled { opacity: .55; cursor: default; }
        #suqi-review.feedback-only button { min-height: 44px; }
        #suqi-review header { display: flex; align-items: center; gap: 6px; flex-wrap: wrap;
          border-radius: 9px; padding: 6px; background: #211916f5; box-shadow: 0 2px 12px #120b08bb; }
        #suqi-review section { margin-top: 6px; max-height: min(55vh, 400px); overflow: auto;
          background: #261d19; border: 1px solid #9f8064; border-radius: 9px; padding: 12px; touch-action: pan-y; }
        #suqi-review label { display: grid; gap: 3px; margin-bottom: 7px; }
        #suqi-review select { max-width: min(310px, calc(100vw - 55px)); min-width: 214px; }
        #suqi-review output { display: block; max-width: min(300px, calc(100vw - 50px)); }
        #review-next-status:not(:empty) { background: #211916; padding: 5px 9px; border-radius: 6px; margin-top: 4px; }
        #suqi-review li { margin: 6px 0; overflow-wrap: anywhere; }
        #suqi-review a { color: #ffddb2; }
        #review-delivery:not(:empty) { margin-top: 4px; padding: 4px 9px; border-radius: 6px; background: #211916f5;
          display: flex; flex-wrap: wrap; align-items: center; gap: 5px; }
        #review-delivery:empty { display: none; }
        #suqi-mark-layer { position: fixed; inset: 0; z-index: 199; cursor: crosshair; touch-action: none; }
        #suqi-pin { display: grid; place-items: center; position: fixed; z-index: 201; pointer-events: none;
          width: 26px; height: 26px; transform: translate(-50%, -50%); color: #3e171f; background: #ffd4a5;
          border-radius: 50%; border: 2px solid #6f333b; font: bold 18px system-ui; }
        #suqi-note { position: fixed; inset: auto 0 max(12px, env(safe-area-inset-bottom)); margin-inline: auto;
          width: min(365px, calc(100vw - 42px)); color: #fff6e6; background: #2c211c; border: 1px solid #cfad88;
          border-radius: 10px; padding: 13px; font: 15px/1.45 system-ui, sans-serif; touch-action: auto;
          max-height: 70dvh; overflow: auto; }
        #suqi-note h2 { font-size: 17px; margin: 0 0 6px; }
        #suqi-note p { margin: 0 0 8px; color: #e5ccb4; }
        #suqi-note textarea { width: 100%; box-sizing: border-box; resize: vertical; min-height: 74px;
          padding: 9px; color: #251a17; background: #fff4e6; border-radius: 6px; font: inherit; touch-action: auto; }
        #suqi-note footer { display: flex; gap: 8px; justify-content: end; margin-top: 5px; }
        #suqi-note::backdrop { background: #170c0929; }
        #suqi-note footer { flex-wrap: wrap; }
        #suqi-note [hidden] { display: none; }
        #suqi-review [hidden], #suqi-mark-layer[hidden], #suqi-pin[hidden] { display: none; }
    `;
    document.head.append(style);

    const toolbar = document.createElement("aside");
    toolbar.id = "suqi-review";
    toolbar.classList.toggle("feedback-only", feedbackOnly);
    toolbar.setAttribute("aria-label", feedbackOnly ? "试玩反馈" : "走查模式");
    toolbar.innerHTML = `
      <header>
        <button type="button" id="review-feedback" hidden>反馈</button>
        <button type="button" id="review-mark" aria-pressed="false">点画面记问题</button>
        <button type="button" id="review-next" disabled>下一步</button>
        <button type="button" id="review-scenes" aria-expanded="false">定位场景</button>
        <button type="button" id="review-notes" aria-expanded="false">已记录</button>
      </header>
      <output id="review-next-status" aria-live="polite"></output>
      <div id="review-delivery" aria-live="polite"></div>
      <section id="review-panel" hidden>
        <label>场景<select id="review-scene"></select></label>
        <label>要看的环节<select id="review-entry"></select></label>
        <button type="button" id="review-jump" disabled>前往</button>
        <output id="review-status" aria-live="polite">场景准备中…</output>
      </section>
      <section id="review-inbox" hidden><output aria-live="polite"></output><ol></ol></section>`;
    const layer = document.createElement("div");
    layer.id = "suqi-mark-layer";
    layer.hidden = true;
    const pin = document.createElement("div");
    pin.id = "suqi-pin";
    pin.textContent = "+";
    pin.hidden = true;
    const dialog = document.createElement("dialog");
    dialog.id = "suqi-note";
    dialog.innerHTML = `<form>
        <h2>试玩反馈</h2>
        <p id="review-location"></p>
        <textarea aria-label="问题备注" placeholder="这里有什么问题？" required maxlength="2000" enterkeyhint="done"></textarea>
        <p role="status" id="review-save-status"></p>
        <p id="review-public-notice" hidden>在 GitHub 提交后，反馈会出现在公开问题列表。</p>
        <footer><button type="button">取消</button><button type="submit">保存备注</button></footer>
      </form>`;
    document.body.append(layer, toolbar, pin, dialog);

    const byId = id => document.getElementById(id);
    const feedback = byId("review-feedback");
    const mark = byId("review-mark");
    const scenes = byId("review-scenes");
    const notes = byId("review-notes");
    const panel = byId("review-panel");
    const inbox = byId("review-inbox");
    const scene = byId("review-scene");
    const entry = byId("review-entry");
    const go = byId("review-jump");
    const status = byId("review-status");
    const locationText = byId("review-location");
    const saveStatus = byId("review-save-status");
    const textarea = dialog.querySelector("textarea");
    const save = dialog.querySelector("button[type=submit]");
    const cancel = dialog.querySelector("button[type=button]");
    const form = dialog.querySelector("form");
    const version = document.querySelector('meta[name="review-build"]')?.content || location.pathname.split("/").filter(Boolean).pop() || "D6";
    if (feedbackOnly) {
        byId("review-next").hidden = true;
        scenes.hidden = true;
    }
    if (issueUrl) {
        notes.hidden = true;
        feedback.hidden = false;
        save.textContent = "去 GitHub 提交";
        byId("review-public-notice").hidden = false;
        if (!feedbackOnly) {
            const source = document.createElement("a");
            source.href = "gameplay-source.zip";
            source.textContent = "玩法源码";
            toolbar.querySelector("header").append(source);
        }
    }
    let player;
    let catalog = [];
    let context = {};
    let draft;
    let armed = false;
    const deliveryStatus = byId("review-delivery");
    const storageKey = repository ? `suqi-feedback-pending:${repository}` : "";
    const latestDraftKey = repository ? `suqi-feedback-draft:${repository}` : "";
    if (repository) restorePending();

    const command = request => player?.(JSON.stringify(request));
    const fillEntries = () => {
        const options = catalog.find(item => item.id === scene.value)?.entries || [];
        entry.replaceChildren(...options.map(item => new Option(item.label, item.beat)));
    };
    window.suqiReview = {
        feedbackOnly,
        attachPlayer(callback, serialized) {
            player = callback;
            if (feedbackOnly) {
                if (armed) command({ action: "freeze" });
                return;
            }
            byId("review-next").disabled = false;
            catalog = JSON.parse(serialized);
            scene.replaceChildren(...catalog.map(item => new Option(item.label && item.label !== item.chapter
                ? `${item.chapter} · ${item.label}` : `${item.chapter} · ${item.id}`, item.id)));
            fillEntries();
            go.disabled = catalog.length === 0;
            status.textContent = "";
            const target = new URLSearchParams(location.hash.slice(1));
            const targetStep = catalog.find(item => item.id === target.get("step"));
            const beat = Number(target.get("beat"));
            if (targetStep && target.has("beat") && Number.isSafeInteger(beat) && beat >= 0) {
                scene.value = targetStep.id;
                fillEntries();
                if (!targetStep.entries.some(item => item.beat === beat)) {
                    entry.add(new Option(`环节 ${beat}`, beat));
                }
                entry.value = String(beat);
                setPanel(panel, scenes, true);
                status.textContent = "已选好要复验的环节，点「前往」。";
            }
        },
        detachPlayer(callback) {
            if (player === callback) {
                player = undefined;
                byId("review-next").disabled = true;
                go.disabled = true;
                status.textContent = "当前已离开爱情篇。刷新此走查页可回到开场。";
            }
        },
        receiveContext(serialized) { context = JSON.parse(serialized); },
        nextNotice(message) {
            const notice = byId("review-next-status");
            notice.textContent = message;
            clearTimeout(this.noticeTimer);
            this.noticeTimer = setTimeout(() => { notice.textContent = ""; }, 3000);
        },
        jumpDone(ok, message) {
            go.disabled = false;
            status.textContent = ok ? "" : message || "请用游戏里的加载按钮继续。";
            if (ok) setPanel(panel, scenes, false);
            canvas.focus({ preventScroll: true });
        },
    };
    function setPanel(element, toggle, open) {
        element.hidden = !open;
        toggle.setAttribute("aria-expanded", String(open));
    }

    function arm(value) {
        armed = value;
        layer.hidden = !value;
        mark.setAttribute("aria-pressed", String(value));
        mark.textContent = value ? "取消标注" : "点画面记问题";
        if (value) {
            setPanel(panel, scenes, false);
            setPanel(inbox, notes, false);
            context = {};
            command({ action: "freeze" });
        } else {
            command({ action: "play" });
        }
    }
    function endNote() {
        draft = undefined;
        pin.hidden = true;
        textarea.value = "";
        arm(false);
        canvas.focus({ preventScroll: true });
    }

    mark.addEventListener("click", () => arm(!armed));
    feedback.addEventListener("click", () => {
        if (armed) arm(false);
        context = {};
        command({ action: "freeze" });
        const bounds = canvas.getBoundingClientRect();
        draft = captureContext(bounds);
        openNote(draft.chapter);
    });
    byId("review-next").addEventListener("click", () => {
        if (armed) arm(false);
        setPanel(panel, scenes, false);
        setPanel(inbox, notes, false);
        if (player) command({ action: "next" });
        else window.suqiReview.nextNotice("场景准备中，请稍等。");
        canvas.focus({ preventScroll: true });
    });
    scenes.addEventListener("click", () => {
        if (armed) arm(false);
        setPanel(inbox, notes, false);
        setPanel(panel, scenes, panel.hidden);
    });
    scene.addEventListener("change", fillEntries);
    function jump(step, beat) {
        go.disabled = true;
        status.textContent = "正在前往…";
        command({ action: "jump", step, beat });
    }
    go.addEventListener("click", () => jump(scene.value, Number(entry.value)));
    async function refreshNotes(show) {
        try {
            const response = await fetch("/_review/notes", { cache: "no-store" });
            if (!response.ok) throw new Error();
            const records = await response.json();
            notes.textContent = `已记录 ${records.length}`;
            if (!show) return;
            inbox.querySelector("output").textContent = records.length ? "最近记录" : "还没有记录";
            const rows = records.map(record => {
                const li = document.createElement("li");
                const link = document.createElement("a");
                link.href = record.screenshot;
                link.target = "_blank";
                link.rel = "noopener";
                link.textContent = "截图";
                li.append(`${record.chapter || "游戏画面"} · ${record.text} `, link);
                if (player && catalog.some(item => item.id === record.step)) {
                    const reopen = document.createElement("button");
                    reopen.type = "button";
                    reopen.textContent = "回到该环节";
                    reopen.addEventListener("click", () => {
                        const item = catalog.find(value => value.id === record.step);
                        scene.value = item.id;
                        fillEntries();
                        if (item.entries.some(value => value.beat === Number(record.beat))) entry.value = record.beat;
                        setPanel(inbox, notes, false);
                        setPanel(panel, scenes, true);
                        jump(record.step, Math.max(0, Number(record.beat)));
                    });
                    li.append(" ", reopen);
                }
                return li;
            });
            inbox.querySelector("ol").replaceChildren(...rows);
        } catch {
            if (show) inbox.querySelector("output").textContent = "暂时读不到本机记录，请稍后再试。";
        }
    }

    notes.addEventListener("click", () => {
        if (armed) arm(false);
        setPanel(panel, scenes, false);
        setPanel(inbox, notes, inbox.hidden);
        if (!inbox.hidden) refreshNotes(true);
    });
    if (!issueUrl) refreshNotes(false);

    function captureContext(bounds) {
        const page = document.body.classList;
        const chapter = page.contains("hy-town-home") ? "苏七镇开屏"
            : page.contains("hy-welcome-menu") ? "爱情篇封面"
            : page.contains("hy-return-menu") ? "续玩页"
            : page.contains("hy-completion-menu") ? "爱情篇结算" : "游戏画面";
        return { version, chapter, ...context, width: Math.round(bounds.width), height: Math.round(bounds.height) };
    }

    function openNote(location) {
        textarea.value = "";
        saveStatus.textContent = "";
        locationText.textContent = location;
        dialog.showModal();
        textarea.focus();
    }

    layer.addEventListener("click", event => {
        const bounds = canvas.getBoundingClientRect();
        const x = (event.clientX - bounds.left) / bounds.width;
        const y = (event.clientY - bounds.top) / bounds.height;
        if (!armed || !(x >= 0 && x <= 1 && y >= 0 && y <= 1)) return;
        draft = { ...captureContext(bounds), x, y };
        if (context.stageTransform) {
            const [originX, originY, unitX, unitY] = context.stageTransform;
            if (unitX > 0 && unitY > 0) {
                draft.stagePoint = [Math.round((x - originX) / unitX), Math.round((y - originY) / unitY)];
            }
        }
        if (!issueUrl) {
            const screenshot = document.createElement("canvas");
            const ratio = Math.min(1, 1000 / Math.max(canvas.width, canvas.height));
            screenshot.width = Math.round(canvas.width * ratio);
            screenshot.height = Math.round(canvas.height * ratio);
            const graphics = screenshot.getContext("2d");
            graphics.drawImage(canvas, 0, 0, screenshot.width, screenshot.height);
            graphics.strokeStyle = "#ffe1a8";
            graphics.lineWidth = 3;
            graphics.beginPath();
            graphics.arc(x * screenshot.width, y * screenshot.height, 11, 0, 2 * Math.PI);
            graphics.stroke();
            draft.id = crypto.randomUUID();
            draft.image = screenshot.toDataURL("image/jpeg", .88);
        }
        pin.style.left = `${event.clientX}px`;
        pin.style.top = `${event.clientY}px`;
        pin.hidden = false;
        const chapter = draft.chapter;
        const point = draft.stagePoint?.join(", ") || `${Math.round(x * 100)}%, ${Math.round(y * 100)}%`;
        openNote(issueUrl ? `${chapter} · 落点 ${point}` : `${chapter} · 将附上截图与点击位置`);
    });
    cancel.addEventListener("click", () => dialog.close());
    dialog.addEventListener("close", endNote);
    document.addEventListener("keydown", event => {
        if (event.key === "Escape" && armed && !dialog.open) arm(false);
    });
    form.addEventListener("submit", async event => {
        event.preventDefault();
        if (!draft || !textarea.value.trim()) return;
        if (issueUrl) {
            if (!repository) {
                saveStatus.textContent = "反馈地址暂不可用，内容仍在表单里。";
                return;
            }
            const text = textarea.value.trim();
            const title = `[试玩] ${draft.chapter || draft.step || "游戏画面"} · ${text.replace(/\s+/g, " ").slice(0, 36)}`;
            const details = [
                `版本：${version}`,
                `章节：${draft.chapter || "开场"}`,
                `场景：${draft.step || "开场"} · 环节 ${draft.beat ?? "-"} · ${draft.mode || "-"} / ${draft.phase || "-"}`,
                `可视画布：${draft.width} × ${draft.height} CSS px`,
            ];
            if (Number.isFinite(draft.x) && Number.isFinite(draft.y)) {
                details.push(`落点：${(draft.x * 100).toFixed(1)}%, ${(draft.y * 100).toFixed(1)}%`);
            }
            if (draft.stagePoint) details.push(`游戏坐标（360 × 640 基准）：${draft.stagePoint.join(", ")}`);
            if (draft.step && Number.isSafeInteger(draft.beat) && draft.beat >= 0) {
                const replay = new URL("./", location.href);
                replay.hash = new URLSearchParams({ step: draft.step, beat: draft.beat }).toString();
                details.push(`[定位复验（打开后点「前往」）](${replay.href})`);
            }
            const issue = { title, body: `${text}\n\n${details.join("\n")}` };
            try { sessionStorage.setItem(latestDraftKey, JSON.stringify(issue)); } catch { /* The links still work. */ }
            const link = issueLink(issue, "打开 GitHub 草稿");
            deliveryStatus.replaceChildren(link);
            if (link.dataset.copyBody) {
                deliveryStatus.prepend("这条反馈较长，请复制正文后粘贴到 GitHub。", copyDraft(issue.body));
            } else {
                link.click();
            }
            dialog.close();
            return;
        }
        save.disabled = true;
        saveStatus.textContent = "正在保存到本机…";
        try {
            const response = await fetch("/_review/notes", {
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ ...draft, text: textarea.value }),
            });
            const result = await response.json();
            if (!response.ok) throw new Error(result.error);
            dialog.close();
            refreshNotes(false);
        } catch (error) {
            saveStatus.textContent = error.message || "保存失败，备注还在，可以重试。";
        } finally {
            save.disabled = false;
        }
    });

    function issueLink({ title, body }, text) {
        const target = new URL(issuePage);
        target.searchParams.set("title", title);
        target.searchParams.set("body", body);
        const link = document.createElement("a");
        if (target.href.length > 6500) {
            target.searchParams.delete("body");
            link.dataset.copyBody = "true";
        }
        link.href = target.href;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = text;
        return link;
    }

    function copyDraft(body) {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = "复制正文";
        button.addEventListener("click", async () => {
            try {
                await navigator.clipboard.writeText(body);
                button.textContent = "已复制";
            } catch {
                const field = document.createElement("textarea");
                field.setAttribute("aria-label", "完整反馈正文");
                field.readOnly = true;
                field.value = body;
                button.replaceWith(field);
                field.focus();
                field.select();
            }
        });
        return button;
    }

    function restorePending() {
        try {
            const oldDrafts = JSON.parse(sessionStorage.getItem(storageKey) || "[]");
            const latest = JSON.parse(sessionStorage.getItem(latestDraftKey) || "null");
            const saved = Array.isArray(oldDrafts) ? oldDrafts : [];
            for (const item of [latest, ...saved]) {
                if (typeof item?.title === "string" && typeof item.body === "string") {
                    const link = issueLink(item, "打开之前的草稿");
                    if (link.dataset.copyBody) deliveryStatus.append(copyDraft(item.body));
                    deliveryStatus.append(link);
                }
            }
        } catch {
            // A blocked or invalid session cache should not prevent new feedback.
        }
    }
})();
