(() => {
    "use strict";
    const posterName = "苏七镇奇缘-爱情篇海报.png";
    const invitation = "我玩完了阿鱼一个人做的《苏七镇奇缘》爱情篇。她把自己和 Toretto 的故事做进了游戏，玩到最后，我被打动了。也想邀你来玩。";

    const posterUrl = document.currentScript.dataset.poster;
    const friendsUrl = document.currentScript.dataset.friends || new URL("friends.html", location.href).href;

    async function loadPoster() {
        const response = await fetch(posterUrl);
        if (!response.ok) throw new Error("Poster is unavailable");
        const blob = await response.blob();
        if (blob.type !== "image/png" || !blob.size) throw new Error("Poster is not a PNG");
        return new File([blob], posterName, {type: "image/png"});
    }

    function shareDialog(file) {
        const url = URL.createObjectURL(file);
        const shareData = {files: [file], title: "苏七镇奇缘", text: invitation, url: friendsUrl};
        const dialog = document.createElement("dialog");
        dialog.className = "hy-share-dialog";
        dialog.setAttribute("aria-labelledby", "hy-share-title");
        dialog.innerHTML = `
            <header><h2 id="hy-share-title">分享并邀请朋友玩</h2>
                <form method="dialog"><button type="submit">关闭</button></form>
            </header>
            <img alt="爱情篇邀请海报，扫码打开朋友试玩入口">
            <div class="hy-share-actions">
                <button type="button" data-share hidden>分享海报</button>
                <a download>保存海报</a>
                <button type="button" data-copy>复制试玩链接</button>
            </div>
            <p role="status"></p>
        `;
        dialog.querySelector("img").src = url;
        const download = dialog.querySelector("a");
        download.href = url;
        download.download = posterName;
        const status = dialog.querySelector("[role=status]");
        const systemShare = dialog.querySelector("[data-share]");
        if (typeof navigator.share === "function" && navigator.canShare?.(shareData)) {
            systemShare.hidden = false;
            systemShare.onclick = async () => {
                try {
                    await navigator.share(shareData);
                } catch (error) {
                    if (error.name !== "AbortError") status.textContent = "可以保存海报后发给朋友。";
                }
            };
        }
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
            URL.revokeObjectURL(url);
            document.getElementById("canvas")?.focus();
        }, {once: true});
        document.body.appendChild(dialog);
        dialog.showModal();
    }

    let generating = false;
    window.suqiCompletionShare = {
        async open() {
            if (generating || document.querySelector(".hy-share-dialog")) return;
            generating = true;
            try {
                shareDialog(await loadPoster());
            } catch {
                window.alert("海报暂时没生成成功，轻点分享再试一次。");
            } finally {
                generating = false;
            }
        }
    };
})();
