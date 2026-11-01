// 内置 TgSearch189（AndroidCatVodSpider/spider/TgSearch189.java）：pansou 搜索天翼云盘分享，detail 列出视频。实现见 pan/tgsearch.js。
// ext 可选：API 地址或 { api_urls, siteurl, sources }，默认 https://so.252035.xyz/api/search
import { tgSearch } from './pan/tgsearch.js';

export default tgSearch('tianyi');
