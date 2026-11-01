// 内置移动云盘分享爬虫，对应 jar 的 csp_YiDongYun（AndroidCatVodSpider/spider/YiDongYun.java）：detail(id) 的 id 为分享链接，列出其中的视频。
// 凭证来自 ext（无则用 local 里刷新过的值），见 pan/yidong.js，无凭证时 play 返回 msg 提示。
import { shareDetail, play, seedCreds } from './pan/cloud.js';

export default {
    // 同 jar：ext 为原始凭证串（也可为 Cloud 式 JSON 对象）
    init(ext) { seedCreds(ext, 'yun_cookie'); },
    home() { return JSON.stringify({ class: [] }); },
    homeVod() { return JSON.stringify({ list: [] }); },
    category() { return JSON.stringify({ list: [] }); },
    detail(id) { return JSON.stringify({ list: [shareDetail(id)] }); },
    search() { return JSON.stringify({ list: [] }); },
    play(flag, id) { return play(flag, id); },
};
