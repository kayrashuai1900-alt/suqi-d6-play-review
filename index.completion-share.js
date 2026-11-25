(() => {
    "use strict";
    const invitation = "我玩完了阿鱼一个人做的《苏七镇奇缘》爱情篇。她把自己和 Toretto 的故事做进了游戏，玩到最后，我被打动了。也想邀你来玩。";
    const playingInvitation = "我在玩阿鱼一个人做的《苏七镇奇缘》。她把自己和 Toretto 的故事做成了六关，玩完还能赴宴、去村里种田。也想邀你来玩。";
    const script = document.currentScript.dataset;
    const posters = script.posters ? JSON.parse(script.posters) : [{url: script.poster}];
    const friendsUrl = script.friends || new URL("friends.html", location.href).href;
    const files = new Map();

    function loadPoster({url, id}) {
        if (!files.has(url)) {
            const request = (async () => {
                const response = await fetch(url);
                if (!response.ok) throw new Error("Poster is unavailable");
                const blob = await response.blob();
                if (blob.type !== "image/png" || !blob.size) throw new Error("Poster is not a PNG");
                const suffix = id ? `-P${id}` : "";
                return new File([blob], `苏七镇奇缘-爱情篇海报${suffix}.png`, {type: "image/png"});
            })().catch(error => {
                files.delete(url);
                throw error;
            });
            files.set(url, request);
        }
        return files.get(url);
    }

    function open(origin, onClose) {
        if (document.querySelector(".hy-share-dialog")) return false;
        const dialog = document.createElement("dialog");
        dialog.className = "hy-share-dialog";
        dialog.setAttribute("aria-labelledby", "hy-share-title");
        dialog.innerHTML = `
            <header>
                <h2 id="hy-share-title" tabindex="-1" autofocus>分享海报</h2>
                <form method="dialog">
                    <button class="hy-share-close" type="submit" aria-label="关闭">
                        <span aria-hidden="true">×</span>
                    </button>
                </form>
            </header>
            <img alt="爱情篇分享海报" hidden>
            <div class="hy-share-gallery">
                <span data-position aria-live="polite"></span>
                <button type="button" data-next>
                    <span aria-hidden="true">↻</span><span data-next-label>换一张</span>
                </button>
            </div>
            <div class="hy-share-actions">
                <a download hidden>保存海报</a>
                <button type="button" data-share hidden>分享海报</button>
            </div>
            <button class="hy-share-copy" type="button" data-copy>复制试玩链接</button>
            <p role="status"></p>
        `;
        const image = dialog.querySelector("img");
        const gallery = dialog.querySelector(".hy-share-gallery");
        const next = dialog.querySelector("[data-next]");
        const nextLabel = next.querySelector("[data-next-label]");
        const position = dialog.querySelector("[data-position]");
        const download = dialog.querySelector("a[download]");
        const status = dialog.querySelector("[role=status]");
        const systemShare = dialog.querySelector("[data-share]");
        let index = -1;
        let activeUrl;
        let shareData;

        async function showPoster(target) {
            next.disabled = true;
            status.textContent = "海报加载中…";
            let imageUrl;
            try {
                const file = await loadPoster(posters[target]);
                if (!dialog.open) return;
                imageUrl = URL.createObjectURL(file);
                const loaded = new Image();
                loaded.src = imageUrl;
                await loaded.decode();
                if (!dialog.open) return;

                const text = origin === "playing" ? playingInvitation : invitation;
                const selection = {files: [file], title: "苏七镇奇缘", text, url: friendsUrl};
                const canShare = typeof navigator.share === "function" && navigator.canShare?.(selection);
                image.src = imageUrl;
                image.alt = `爱情篇分享海报，第 ${target + 1} 张，共 ${posters.length} 张`;
                image.hidden = false;
                download.href = imageUrl;
                download.download = file.name;
                download.hidden = false;
                shareData = selection;
                systemShare.hidden = !canShare;
                if (activeUrl) URL.revokeObjectURL(activeUrl);
                activeUrl = imageUrl;
                imageUrl = undefined;
                index = target;
                position.textContent = `${index + 1} / ${posters.length}`;
                gallery.hidden = posters.length === 1;
                nextLabel.textContent = "换一张";
                status.textContent = "";
            } catch {
                if (dialog.open) {
                    files.delete(posters[target].url);
                    if (index < 0) nextLabel.textContent = "重试";
                    status.textContent = "海报加载失败，请重试。";
                }
            } finally {
                if (imageUrl) URL.revokeObjectURL(imageUrl);
                next.disabled = false;
            }
        }

        next.onclick = () => showPoster((index + 1) % posters.length);
        systemShare.onclick = async () => {
            try {
                await navigator.share(shareData);
            } catch (error) {
                if (error.name !== "AbortError") status.textContent = "可以保存海报后发给朋友。";
            }
        };
        dialog.querySelector("[data-copy]").onclick = async () => {
            try {
                await navigator.clipboard.writeText(friendsUrl);
                status.textContent = "试玩链接已复制";
            } catch {
                const link = document.createElement("a");
                link.href = friendsUrl;
                link.textContent = "打开朋友试玩入口";
                link.target = "_blank";
                link.rel = "noopener";
                status.replaceChildren(link);
            }
        };
        dialog.addEventListener("close", () => {
            dialog.remove();
            if (activeUrl) URL.revokeObjectURL(activeUrl);
            document.getElementById("canvas")?.focus();
            if (typeof onClose === "function") onClose();
        }, {once: true});
        document.body.appendChild(dialog);
        dialog.showModal();
        showPoster(0);
        return true;
    }

    window.suqiCompletionShare = {open};
})();
