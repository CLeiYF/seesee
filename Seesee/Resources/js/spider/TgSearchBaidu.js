// 内置 TgSearchBaidu（AndroidCatVodSpider/spider/TgSearchBaidu.java）：pansou 搜索百度网盘分享，detail 列出视频。实现见 pan/tgsearch.js。
// ext 可选：API 地址或 { api_urls, siteurl, sources }，默认 https://so.252035.xyz/api/search
import { tgSearch } from './pan/tgsearch.js';

export default tgSearch('baidu');
