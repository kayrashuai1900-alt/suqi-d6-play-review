(() => {
    "use strict";
    const posterName = "苏七镇奇缘-爱情篇海报.png";
    const invitation = "来玩《苏七镇奇缘》吧，一起看看阿鱼和 Toretto 的爱情故事。";

    async function createPoster(albumPng) {
        const image = new Image();
        image.src = "data:image/png;base64," + albumPng;
        await image.decode();
        const width = Math.max(720, image.naturalWidth);
        const albumHeight = Math.round(image.naturalHeight * width / image.naturalWidth);
        const qrSize = Math.round(width * 0.22);
        const margin = Math.round(width * 0.07);
        const footerHeight = qrSize + margin;
        const poster = document.createElement("canvas");
        poster.width = width;
        poster.height = albumHeight + footerHeight;
        const ink = poster.getContext("2d");
        ink.drawImage(image, 0, 0, width, albumHeight);
        ink.fillStyle = "#efdfc3";
        ink.fillRect(0, albumHeight, width, footerHeight);
        const qrX = margin;
        const qrY = albumHeight + Math.floor(margin / 2);
        ink.fillStyle = "#fff6e5";
        ink.fillRect(qrX, qrY, qrSize, qrSize);
        ink.strokeStyle = "#9c7861";
        ink.lineWidth = Math.max(1, Math.round(width * 0.002));
        ink.strokeRect(qrX, qrY, qrSize, qrSize);
        ink.fillStyle = "#71523e";
        ink.textBaseline = "middle";
        ink.textAlign = "center";
        ink.font = `${Math.round(width * 0.024)}px "PingFang SC", "Noto Sans SC", sans-serif`;
        ink.fillText("二维码预留区", qrX + qrSize / 2, qrY + qrSize / 2);
        ink.fillStyle = "#773731";
        ink.textAlign = "left";
        ink.font = `600 ${Math.round(width * 0.044)}px "Songti SC", "Noto Serif CJK SC", serif`;
        ink.fillText("即刻扫，畅游苏七镇", qrX + qrSize + margin, qrY + qrSize / 2);
        const blob = await new Promise(resolve => poster.toBlob(resolve, "image/png"));
        if (!blob) throw new Error("Poster generation failed");
        return new File([blob], posterName, {type: "image/png"});
    }

    function shareDialog(file) {
        const url = URL.createObjectURL(file);
        const friendsUrl = new URL("friends.html", location.href).href;
        const shareData = {files: [file], title: "苏七镇奇缘", text: invitation, url: friendsUrl};
        const dialog = document.createElement("dialog");
        dialog.className = "hy-share-dialog";
        dialog.setAttribute("aria-labelledby", "hy-share-title");
        dialog.innerHTML = `
            <header><h2 id="hy-share-title">分享并邀请朋友玩</h2>
                <form method="dialog"><button type="submit">关闭</button></form>
            </header>
            <img alt="爱情篇结算海报，底部预留二维码位置">
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
        async open(albumPng) {
            if (generating || document.querySelector(".hy-share-dialog")) return;
            generating = true;
            try {
                shareDialog(await createPoster(albumPng));
            } catch {
                window.alert("海报暂时没生成成功，轻点分享再试一次。");
            } finally {
                generating = false;
            }
        }
    };
})();
