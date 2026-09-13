#!/usr/bin/env python3
"""
内置磁力/网盘搜索源生成器。
参考 app/assets/sources/ 中已有的 magnet/pan 源 JSON 格式，
将搜索站点注册表批量生成 source_engine 自有格式 JSON 文件，
并输出到 D:/projects/xso/app/assets/sources/。
"""

import json
from pathlib import Path

SOURCES_DIR = Path(r"D:\projects\xso\app\assets\sources")
BUILTIN_SOURCES_DART = Path(r"D:\projects\xso\app\lib\providers\builtin_sources.dart")

# ---------------------------------------------------------------------------
# 站点注册表
# 每条: {id, name, type, url_template, result_container, result_fields,
#        detail_url_template, detail_content, extractors, headers, note}
# type: "magnet" | "pan"
# url_template: search URL with {{keyword}} and {{page}} placeholders
# result_container: CSS selector for each result row
# result_fields: {name: {selector, attr}} dict
# detail_*: only needed for pan (two-phase) sources
# extractors: list of PanProvider names (baidu/quark/aliyun/123pan/xunlei)
# ---------------------------------------------------------------------------

MAGNET_SOURCES = [
    {
        "id": "builtin.ciliduo.magnet",
        "name": "磁力多",
        "url": "https://ciliduo.org/search/{{keyword}}/{{page}}",
        "container": "div.list-group-item, tr.torrent, div.result-item, article",
        "fields": {
            "title": {"selector": "a, h3 a, .title", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a[href$='.torrent'], a", "attr": "href"},
            "size": {"selector": ".size, td:nth-child(3), span.size", "attr": "text"},
            "date": {"selector": ".date, td:nth-child(4), span.date", "attr": "text"},
        },
        "headers": {"Referer": "https://ciliduo.org/"},
        "note": "国内资源最丰富的磁力搜索引擎之一，千万级磁力数据每日更新，覆盖影视/软件/电子书/游戏等全品类。",
    },
    {
        "id": "builtin.wuji.magnet",
        "name": "无极磁力",
        "url": "https://cili.st/search/{{keyword}}/{{page}}",
        "container": "tr, div.result-item, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2), .size", "attr": "text"},
            "date": {"selector": "td:nth-child(3), .date", "attr": "text"},
        },
        "headers": {"Referer": "https://cili.st/"},
        "note": "国际知名磁力分享站，资源覆盖面广，支持按大小/时间筛选，界面简洁。",
    },
    {
        "id": "builtin.skrbt.magnet",
        "name": "SkrBT",
        "url": "https://skrbtuc.top/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a, .title", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2), .size", "attr": "text"},
            "date": {"selector": "td:nth-child(3), .date", "attr": "text"},
        },
        "headers": {"Referer": "https://skrbtuc.top/"},
        "note": "专注 DHT 网络爬取，索引千万级磁力链接，更新及时，影视/软件/游戏资源丰富。",
    },
    {
        "id": "builtin.cilipa.magnet",
        "name": "磁力爬",
        "url": "https://www.cilipa.me/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.cilipa.me/"},
        "note": "DHT 去中心化磁力搜索，不存储内容仅索引元数据；备用域名 cilipa.cc / cilipa.me。",
    },
    {
        "id": "builtin.lemon.magnet",
        "name": "磁力柠檬",
        "url": "https://lemonuc.top/search/{{keyword}}/{{page}}",
        "container": "div.result-item, tr, article",
        "fields": {
            "title": {"selector": "a, h3 a, .title", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": ".size, td:nth-child(2)", "attr": "text"},
            "date": {"selector": ".date, td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://lemonuc.top/"},
        "note": "干净好用的磁力链和网盘资源搜索引擎，界面清爽，无过多广告干扰。",
    },
    {
        "id": "builtin.eclyun.magnet",
        "name": "磁力云搜索",
        "url": "https://www.eclyun.cc/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.eclyun.cc/"},
        "note": "自称全球资源最丰富的磁力 BT 种子垂直搜索引擎，覆盖影视/音乐/软件/电子书等。",
    },
    {
        "id": "builtin.xingqiu.magnet",
        "name": "磁力星球",
        "url": "https://so5.xingqiu.icu/search/{{keyword}}/{{page}}",
        "container": "div.result, tr, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": ".size, td:nth-child(2)", "attr": "text"},
            "date": {"selector": ".date, td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://so5.xingqiu.icu/"},
        "note": "干净实用的磁力链和网盘资源聚合搜索，同时覆盖磁力与网盘两类源。",
    },
    {
        "id": "builtin.yuhUAGE.magnet",
        "name": "雨花阁磁力",
        "url": "https://www.yuhUAGE.win/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.yuhUAGE.win/"},
        "note": "简单纯粹的磁力搜索引擎，专注磁力资源，界面轻量无冗余。",
    },
    {
        "id": "builtin.bt1207.magnet",
        "name": "BT1207",
        "url": "https://ibt120702.xyz/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://ibt120702.xyz/"},
        "note": "磁力搜索引擎，收录大量影视/软件/游戏资源。",
    },
    {
        "id": "builtin.laowang.magnet",
        "name": "老王磁力",
        "url": "https://ilaowang05.xyz/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://ilaowang05.xyz/"},
        "note": "老王磁力，干净简洁的磁力搜索体验，备选域名 ilaowang.xyz。",
    },
    {
        "id": "builtin.cilijia.magnet",
        "name": "磁力家",
        "url": "https://cilijia.net/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://cilijia.net/"},
        "note": "磁力家，专注磁力链接聚合，覆盖影视/动漫/软件等品类。",
    },
    {
        "id": "builtin.cilihezi.magnet",
        "name": "磁力猫",
        "url": "https://cilihezi.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://cilihezi.com/"},
        "note": "磁力猫（CiliHezi），全能型磁力搜索+导航站，界面清爽，链接有效率较高。",
    },
    {
        "id": "builtin.ddcl.magnet",
        "name": "滴滴磁力",
        "url": "http://ddcl.me/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {},
        "note": "滴滴磁力（DDCL），极简纯搜索框无注册，1秒出结果，稳定性强。",
    },
    {
        "id": "builtin.cltt.magnet",
        "name": "磁力天堂",
        "url": "https://cltt.me/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://cltt.me/"},
        "note": "磁力天堂（CLTT），老牌影视向磁力站，分类细致无弹窗广告，支持大小/时间筛选。",
    },
    {
        "id": "builtin.wujicili.magnet",
        "name": "无极磁力搜索",
        "url": "https://www.wujicili.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.wujicili.com/"},
        "note": "无极磁力，界面简洁操作方便，提供热门榜单与最新更新追踪。",
    },
    {
        "id": "builtin.cilimao.magnet",
        "name": "磁力猫（备用）",
        "url": "https://clm235.xyz/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://clm235.xyz/"},
        "note": "磁力猫备用域名，同样提供磁力链接搜索与 BT 种子下载。",
    },
    {
        "id": "builtin.cilicao.magnet",
        "name": "磁力草搜索",
        "url": "https://www.cilicao.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.cilicao.com/"},
        "note": "磁力草，全网最大磁力搜索引擎，华语地区千万级数据每日更新。",
    },
    {
        "id": "builtin.91bt.magnet",
        "name": "91BT",
        "url": "https://91btbt.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://91btbt.com/"},
        "note": "91BT，最新最热门的 BT 种子磁力链接搜索器。",
    },
    {
        "id": "builtin.52bt.magnet",
        "name": "52BT",
        "url": "https://www.52bt.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.52bt.com/"},
        "note": "52BT，电影/音乐/游戏/小说/电子书 BT 种子磁力最佳搜索神器。",
    },
    {
        "id": "builtin.magnetdog.magnet",
        "name": "磁力狗",
        "url": "https://www.ciligou.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.ciligou.com/"},
        "note": "磁力狗，高级全球种子资源在线搜索库，实时引索全球磁力链接。",
    },
    {
        "id": "builtin.cldi.magnet",
        "name": "磁力帝",
        "url": "https://cldi.top/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://cldi.top/"},
        "note": "磁力帝，资源最多更新最快的磁力链接搜索引擎，千万级影视音乐软件电子书资源。",
    },
    {
        "id": "builtin.btlm.magnet",
        "name": "BT联盟",
        "url": "https://yo.btlm.one/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://yo.btlm.one/"},
        "note": "BT联盟，全球领先的 BT 种子与磁力链接搜索网站。",
    },
    {
        "id": "builtin.sefan.magnet",
        "name": "搜fan",
        "url": "https://gr.sefan.me/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://gr.sefan.me/"},
        "note": "搜fan，磁力搜索神器，通过 DHT 网络实时获取最新 BT 种子并生成磁力链接。",
    },
    {
        "id": "builtin.foxso.magnet",
        "name": "磁力狐",
        "url": "https://bt1.foxso.top/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://bt1.foxso.top/"},
        "note": "磁力狐，专业磁力搜索引擎，专注视频/电影/电视剧/电子书。",
    },
    {
        "id": "builtin.rili6.magnet",
        "name": "轻松磁力",
        "url": "https://rili6.mdjstbbwwj.world/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://rili6.mdjstbbwwj.world/"},
        "note": "轻松磁力搜索，实用磁力搜索引擎，涵盖影视/音乐/书籍/游戏各类资源。",
    },
    {
        "id": "builtin.emoncili.magnet",
        "name": "BT吃力",
        "url": "https://1ve2r3.emoncili.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://1ve2r3.emoncili.com/"},
        "note": "BT吃力，国内资源最全的磁力搜索站之一。",
    },
    {
        "id": "builtin.wuqianso.magnet",
        "name": "吴签磁力",
        "url": "https://wuqiansa.top/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://wuqiansa.top/"},
        "note": "吴签磁力，干净好用的磁力链和网盘资源搜索引擎，同时覆盖磁力与网盘。",
    },
    {
        "id": "builtin.xiongmao.magnet",
        "name": "磁力熊猫",
        "url": "https://xiongmaocl.top/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://xiongmaocl.top/"},
        "note": "磁力熊猫，干净好用的磁力链和网盘资源搜索引擎。",
    },
    {
        "id": "builtin.iyuhUAGE.magnet",
        "name": "雨花阁磁力（新）",
        "url": "https://iyuhUAGE.fun/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://iyuhUAGE.fun/"},
        "note": "雨花阁磁力新版域名，简单纯粹的磁力搜索引擎。",
    },
    # ---- 国际/英文磁力站 ----
    {
        "id": "builtin.torrentgalaxy.magnet",
        "name": "TorrentGalaxy",
        "url": "https://torrentgalaxy.space/search/{{keyword}}/{{page}}",
        "container": "tr, div.torrent-row, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
            "seeders": {"selector": "td:nth-child(4)", "attr": "text"},
        },
        "headers": {"Referer": "https://torrentgalaxy.space/"},
        "note": "TorrentGalaxy，国际知名综合磁力站，英文原版资源丰富，做种数量大下载速度有保障。",
    },
    {
        "id": "builtin.solidtorrents.magnet",
        "name": "SolidTorrents",
        "url": "https://solidtorrents.to/search/{{keyword}}/{{page}}",
        "container": "tr, div.torrent, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
            "seeders": {"selector": "td:nth-child(4)", "attr": "text"},
        },
        "headers": {"Referer": "https://solidtorrents.to/"},
        "note": "SolidTorrents，千万级 torrent 索引，按类别/健康度/上传日期筛选，支持 magnet 直链。",
    },
    {
        "id": "builtin.idope.magnet",
        "name": "iDope",
        "url": "https://idope.se/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
            "seeders": {"selector": "td:nth-child(4)", "attr": "text"},
        },
        "headers": {"Referer": "https://idope.se/"},
        "note": "iDope，KickassTorrents 风格元搜索引擎，自 2016 年运营，移动端友好。",
    },
    {
        "id": "builtin.snowfl.magnet",
        "name": "Snowfl",
        "url": "https://snowfl.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
            "seeders": {"selector": "td:nth-child(4)", "attr": "text"},
        },
        "headers": {"Referer": "https://snowfl.com/"},
        "note": "Snowfl，极简元搜索引擎，支持按大小/来源/时间精细过滤，界面干净广告少。",
    },
    {
        "id": "builtin.torrentseeker.magnet",
        "name": "TorrentSeeker",
        "url": "https://torrentseeker.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://torrentseeker.com/"},
        "note": "TorrentSeeker，简洁无广告设计，关键词自动联想，按相关性/日期排序。",
    },
    {
        "id": "builtin.magnetdl.magnet",
        "name": "MagnetDL",
        "url": "https://www.magnetdl.com/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://www.magnetdl.com/"},
        "note": "MagnetDL，轻量磁力搜索，适合查找较老或冷门资源。",
    },
    {
        "id": "builtin.bitsearch.magnet",
        "name": "Bitsearch",
        "url": "https://bitsearch.to/search/{{keyword}}/{{page}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
            "seeders": {"selector": "td:nth-child(4)", "attr": "text"},
        },
        "headers": {"Referer": "https://bitsearch.to/"},
        "note": "Bitsearch，现代 Torrent 搜索引擎，含分类筛选与健康度指示器。",
    },
    {
        "id": "builtin.knaben.magnet",
        "name": "Knaben（对照·跳过，已有精确源）",
        "url": "",
        "container": "",
        "fields": {},
        "headers": {},
        "note": "SKIP: builtin.knaben.magnet 已在 assets/sources/knaben_magnet.json 中精确定义",
        "skip": True,
    },
]

PAN_SOURCES = [
    {
        "id": "builtin.alipansou.pan",
        "name": "猫狸盘搜",
        "url": "https://www.alipansou.com/search?k={{keyword}}&page={{page}}",
        "container": "div[class*='card'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a.title, .card-title a, h5 a, .name", "attr": "text"},
            "url": {"selector": "a.title, .card-title a, h5 a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["aliyun", "baidu", "quark", "xunlei", "123pan"],
        "headers": {"Referer": "https://www.alipansou.com/"},
        "note": "SKIP: builtin.alipansou.pan 已在 assets/sources/alipansou_pan.json 中精确定义",
        "skip": True,
    },
    {
        "id": "builtin.niceso.pan",
        "name": "奈斯搜索",
        "url": "https://www.niceso.net/search?k={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item, .resource-item",
        "fields": {
            "title": {"selector": "a, .title, h3", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["aliyun", "baidu", "quark", "xunlei", "123pan"],
        "headers": {"Referer": "https://www.niceso.net/"},
        "note": "SKIP: builtin.niceso.pan 已在 assets/sources/niceso_pan.json 中精确定义",
        "skip": True,
    },
    {
        "id": "builtin.pansousou.pan",
        "name": "盘搜搜",
        "url": "http://so.baiduyun.me/s/{{keyword}}/p/{{page}}",
        "container": "div.search-result-item, div[class*='item'], .result-card",
        "fields": {
            "title": {"selector": "a.title, a[class*='link'], h3 a, .name", "attr": "text"},
            "url": {"selector": "a.title, a[class*='link'], h3 a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], .resource-detail, article",
        "extractors": ["baidu", "quark", "aliyun", "123pan", "xunlei"],
        "headers": {},
        "note": "SKIP: builtin.pansousou.pan 已在 assets/sources/pansousou_pan.json 中精确定义",
        "skip": True,
    },
    {
        "id": "builtin.repanso.pan",
        "name": "热盘搜",
        "url": "https://repanso.net/s/{{keyword}}/p/{{page}}",
        "container": "div.search-result-item, div[class*='item'], .resource-card",
        "fields": {
            "title": {"selector": "a.title, a[class*='link'], h3 a, .name", "attr": "text"},
            "url": {"selector": "a.title, a[class*='link'], h3 a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], .resource-detail, article",
        "extractors": ["baidu", "quark", "aliyun", "123pan", "xunlei"],
        "headers": {"Referer": "https://repanso.net/"},
        "note": "SKIP: builtin.repanso.pan 已在 assets/sources/repanso_pan.json 中精确定义",
        "skip": True,
    },
    {
        "id": "builtin.ypansou.pan",
        "name": "易搜",
        "url": "https://yiso.fun/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a, .name", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "xunlei", "123pan"],
        "headers": {"Referer": "https://yiso.fun/"},
        "note": "易搜（yiso.fun），全能多平台检索引擎，兼容百度/夸克/阿里/蓝奏/天翼/迅雷六大网盘。",
    },
    {
        "id": "builtin.xuebapan.pan",
        "name": "学霸盘",
        "url": "https://www.xuebapan.com/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu"],
        "headers": {"Referer": "https://www.xuebapan.com/"},
        "note": "学霸盘，专注百度网盘学习资料（小学/初中/高中/大学/考研/考公），无需注册登录。",
    },
    {
        "id": "builtin.upyunso.pan",
        "name": "UP云搜",
        "url": "https://www.upyunso.com/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["aliyun", "baidu", "quark"],
        "headers": {"Referer": "https://www.upyunso.com/"},
        "note": "UP云搜，最全阿里云盘资源搜索神器，更新快、链接有效性高。",
    },
    {
        "id": "builtin.xiaoso.pan",
        "name": "小不点搜索",
        "url": "https://www.xiaoso.net/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "123pan", "xunlei"],
        "headers": {"Referer": "https://www.xiaoso.net/"},
        "note": "小不点搜索，正版资源搜索引擎，整合多网盘资源，界面清爽。",
    },
    {
        "id": "builtin.h2ero.pan",
        "name": "咕咕云搜索",
        "url": "https://www.h2ero.com/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.h2ero.com/"},
        "note": "咕咕云搜索，百度云盘搜索引擎，响应迅速资源丰富。",
    },
    {
        "id": "builtin.sobaidupan.pan",
        "name": "搜BaiDu盘",
        "url": "https://www.sobaidupan.com/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu"],
        "headers": {"Referer": "https://www.sobaidupan.com/"},
        "note": "搜BaiDu盘，专业百度云盘资源下载与搜索引擎导航。",
    },
    {
        "id": "builtin.xiongdipan.pan",
        "name": "兄弟盘",
        "url": "https://xiongdipan.com/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "xunlei"],
        "headers": {"Referer": "https://xiongdipan.com/"},
        "note": "兄弟盘，云盘资源搜索，支持多平台聚合。",
    },
    {
        "id": "builtin.chaonengsou.pan",
        "name": "超能搜",
        "url": "https://www.chaonengsou.com/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "123pan", "xunlei"],
        "headers": {"Referer": "https://www.chaonengsou.com/"},
        "note": "超能搜，百度网盘搜索神器，资源全面、响应快。",
    },
    {
        "id": "builtin.qileso.pan",
        "name": "奇乐搜",
        "url": "https://www.qileso.com/search?q={{keyword}}&page={{page}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["aliyun", "quark", "baidu"],
        "headers": {"Referer": "https://www.qileso.com/"},
        "note": "奇乐搜，阿里云盘+夸克网盘综合搜索网站，界面简洁。",
    },
    {
        "id": "builtin.panduo.pan",
        "name": "盘多多",
        "url": "http://www.panduoduo.online/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {},
        "note": "盘多多，老牌网盘搜索引擎，资源最丰富但偶有不稳定。",
    },
    {
        "id": "builtin.wowenda.pan",
        "name": "网盘之家",
        "url": "http://www.wowenda.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "xunlei"],
        "headers": {},
        "note": "网盘之家，网盘资源社区，分享活跃资源丰富。",
    },
    {
        "id": "builtin.pansearch.pan",
        "name": "PanSearch",
        "url": "https://www.pansearch.me/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "123pan", "xunlei"],
        "headers": {"Referer": "https://www.pansearch.me/"},
        "note": "PanSearch，支持阿里/夸克/百度等网盘搜索 + 磁力搜索 + Telegram 群搜索的全能聚合引擎。",
    },
    {
        "id": "builtin.lingfengyun.pan",
        "name": "凌风云",
        "url": "https://www.lingfengyun.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "xunlei"],
        "headers": {"Referer": "https://www.lingfengyun.com/"},
        "note": "凌风云，十大网盘搜索引擎汇总站，整合主流网盘搜索入口。",
    },
    {
        "id": "builtin.sosoyunpan.pan",
        "name": "SOSO云盘搜索",
        "url": "https://www.sosoyunpan.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "123pan"],
        "headers": {"Referer": "https://www.sosoyunpan.com/"},
        "note": "SOSO云盘搜索，综合网盘搜索引擎导航，界面清爽。",
    },
    {
        "id": "builtin.daysou.pan",
        "name": "云搜",
        "url": "http://www.daysou.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {},
        "note": "云搜（daysou），老牌网盘搜索引擎，含热搜词与垂直分类。",
    },
    {
        "id": "builtin.wanyipan.pan",
        "name": "万盘资源",
        "url": "https://www.wanpanzy.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "xunlei"],
        "headers": {"Referer": "https://www.wanpanzy.com/"},
        "note": "万盘资源（wanpanzy），整合全网网盘资源的排行前列聚合站。",
    },
    {
        "id": "builtin.pikaso.pan",
        "name": "皮卡搜索",
        "url": "https://www.pikaso.top/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.pikaso.top/"},
        "note": "皮卡搜索，轻量网盘资源搜索，支持多网盘类型。",
    },
    {
        "id": "builtin.jiwake.pan",
        "name": "鸡娃客",
        "url": "https://www.jiwake.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.jiwake.com/"},
        "note": "鸡娃客，教育类网盘资源搜索站，学习资料资源丰富。",
    },
    {
        "id": "builtin.codelicence.pan",
        "name": "云盘4K",
        "url": "https://www.codelicence.cn/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["aliyun", "baidu", "quark"],
        "headers": {"Referer": "https://www.codelicence.cn/"},
        "note": "云盘4K，综合资源搜索引擎，主要覆盖阿里云盘影视与学习资料，无需注册。",
    },
    {
        "id": "builtin.fastsoso.pan",
        "name": "FastSoso",
        "url": "https://www.fastsoso.cn/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.fastsoso.cn/"},
        "note": "FastSoso，极速网盘搜索，响应速度快。",
    },
    {
        "id": "builtin.wopansou.pan",
        "name": "Wopansou",
        "url": "https://www.woqusou.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.woqusou.com/"},
        "note": "Wopansou，网盘搜索工具，界面简洁。",
    },
    {
        "id": "builtin.pan131.pan",
        "name": "盘131",
        "url": "https://www.pan131.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.pan131.com/"},
        "note": "盘131，网盘搜索引擎，收录多平台资源。",
    },
    {
        "id": "builtin.yunpanem.pan",
        "name": "云盘恶魔",
        "url": "https://yunpanem.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://yunpanem.com/"},
        "note": "云盘恶魔，综合性网盘资源搜索引擎。",
    },
    {
        "id": "builtin.panc.pa.pan",
        "name": "胖次搜索",
        "url": "https://www.panc.cc/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.panc.cc/"},
        "note": "胖次搜索，二次元资源丰富的网盘搜索引擎。",
    },
    {
        "id": "builtin.xiaobaipan.pan",
        "name": "小白盘",
        "url": "https://www.xiaobaipan.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.xiaobaipan.com/"},
        "note": "小白盘，轻量网盘搜索工具，界面简洁易用。",
    },
    {
        "id": "builtin.dalipan.pan",
        "name": "大力盘",
        "url": "https://www.dalipan.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.dalipan.com/"},
        "note": "大力盘，网盘资源搜索，支持多平台聚合。",
    },
    {
        "id": "builtin.xiaomapan.pan",
        "name": "小马盘",
        "url": "https://www.xiaomapan.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.xiaomapan.com/"},
        "note": "小马盘，轻量网盘搜索，手机用户友好。",
    },
    {
        "id": "builtin.woqusou.pan",
        "name": "口袋云",
        "url": "https://www.woqusou.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.woqusou.com/"},
        "note": "口袋云（woqusou），便携网盘资源搜索工具。",
    },
    {
        "id": "builtin.wosouyun.pan",
        "name": "我搜云网盘",
        "url": "https://www.wosouyun.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.wosouyun.com/"},
        "note": "我搜云网盘，网盘资源聚合搜索。",
    },
    {
        "id": "builtin.yunpuzi.pan",
        "name": "云铺子",
        "url": "https://www.yunpuzi.net/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "xunlei"],
        "headers": {"Referer": "https://www.yunpuzi.net/"},
        "note": "云铺子，可按网盘/影视/素材/学术/开发/社交等分类精准搜索。",
    },
    {
        "id": "builtin.vpansou.pan",
        "name": "V盘搜",
        "url": "http://www.vpansou.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu"],
        "headers": {},
        "note": "V盘搜，百度网盘搜索引擎，支持多类别切换（电影/种子/小说/电子书/音乐/软件/游戏）。",
    },
    {
        "id": "builtin.wuyasou.pan",
        "name": "乌鸦搜",
        "url": "https://wuyasou.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun", "xunlei"],
        "headers": {"Referer": "https://wuyasou.com/"},
        "note": "乌鸦搜，好用网盘搜索引擎，支持视频/音乐/图片/文档/种子等多分类。",
    },
    {
        "id": "builtin.sopandas.pan",
        "name": "熊猫搜盘",
        "url": "https://www.sopandas.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.sopandas.com/"},
        "note": "熊猫搜盘，综合网盘资源搜索。",
    },
    {
        "id": "builtin.cuppaso.pan",
        "name": "咔帕搜索",
        "url": "https://www.cuppaso.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://www.cuppaso.com/"},
        "note": "咔帕搜索，轻量网盘搜索工具。",
    },
    {
        "id": "builtin.xiongbeng.pan",
        "name": "熊崩搜索",
        "url": "https://xiongbeng.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": ["baidu", "quark", "aliyun"],
        "headers": {"Referer": "https://xiongbeng.com/"},
        "note": "熊崩搜索，综合性网盘资源搜索引擎。",
    },
    {
        "id": "builtin.lanzou.magnet",
        "name": "蓝奏云搜索",
        "url": "https://www.lanzoui.com/search?q={{keyword}}",
        "container": "div[class*='item'], div[class*='result'], .search-item",
        "fields": {
            "title": {"selector": "a, .title, h3 a", "attr": "text"},
            "url": {"selector": "a", "attr": "href"},
        },
        "detail_content": "div[class*='article'], div[class*='content'], article",
        "extractors": [],
        "headers": {"Referer": "https://www.lanzoui.com/"},
        "note": "蓝奏云直搜，轻量文件分享盘，适合找软件/文档类资源。",
    },
    {
        "id": "builtin.mazey.magnet",
        "name": "磁力草（备用）",
        "url": "https://cilicao.com/search?q={{keyword}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://cilicao.com/"},
        "note": "磁力草备用域名，华语最大磁力搜索引擎。",
    },
    {
        "id": "builtin.migu.magnet",
        "name": "米咕磁力",
        "url": "https://migu.moe/search?q={{keyword}}",
        "container": "tr, div.result, article",
        "fields": {
            "title": {"selector": "a, h3 a", "attr": "text"},
            "url": {"selector": "a[href*='magnet'], a", "attr": "href"},
            "size": {"selector": "td:nth-child(2)", "attr": "text"},
            "date": {"selector": "td:nth-child(3)", "attr": "text"},
        },
        "headers": {"Referer": "https://migu.moe/"},
        "note": "米咕磁力，年轻化磁力搜索引擎，界面清爽。",
    },
]


# ---------------------------------------------------------------------------
# JSON 生成逻辑（对齐 schema.dart 自有格式）
# ---------------------------------------------------------------------------

def _extract_update_url(url_template: str) -> str:
    """从 URL 模板中提取站点根域名作为 updateUrl。"""
    try:
        from urllib.parse import urlparse
        # 去掉 {{...}} 占位符后再解析
        clean = url_template.replace("{{keyword}}", "").replace("{{page}}", "").replace("{{detailUrl}}", "")
        return urlparse(clean).scheme + "://" + urlparse(clean).netloc
    except Exception:
        return url_template


def build_magnet_source(site: dict) -> dict:
    result_fields = {}
    for fname, fdef in site["fields"].items():
        result_fields[fname] = {"selector": fdef["selector"], "attr": fdef.get("attr", "text")}

    source = {
        "meta": {
            "id": site["id"],
            "name": site["name"],
            "type": "magnet",
            "version": 1,
            "engine": "script",
            "author": "builtin",
            "updateUrl": _extract_update_url(site["url"]),
        },
        "search": {
            "request": {
                "url": site["url"],
                "method": "GET",
                "headers": site.get("headers", {}),
                "charset": "utf-8",
            },
            "result": {
                "container": site["container"],
                "fields": result_fields,
            },
        },
    }
    if "note" in site:
        source["template_note"] = site["note"]
    return source


def build_pan_source(site: dict) -> dict:
    result_fields = {}
    for fname, fdef in site["fields"].items():
        result_fields[fname] = {"selector": fdef["selector"], "attr": fdef.get("attr", "text")}

    source = {
        "meta": {
            "id": site["id"],
            "name": site["name"],
            "type": "pan",
            "version": 1,
            "engine": "script",
            "author": "builtin",
            "updateUrl": _extract_update_url(site["url"]),
        },
        "search": {
            "request": {
                "url": site["url"],
                "method": "GET",
                "headers": site.get("headers", {}),
                "charset": "utf-8",
            },
            "result": {
                "container": site["container"],
                "fields": result_fields,
            },
        },
    }
    if site.get("detail_content"):
        # 详情页 URL：用 base domain + /s/{{detailUrl}} 或保留原路径结构
        base = _extract_update_url(site["url"])
        source["detail"] = {
            "request": {"url": base + "/s/{{detailUrl}}"},
            "content": site["detail_content"],
            "extractors": site.get("extractors", ["baidu", "quark", "aliyun", "123pan"]),
        }
    if "note" in site:
        source["template_note"] = site["note"]
    return source


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def main():
    SOURCES_DIR.mkdir(parents=True, exist_ok=True)

    manifest_entries = []

    # 生成磁力源（跳过 skip=True 的条目）
    for site in MAGNET_SOURCES:
        if site.get("skip"):
            print(f"  ⏭ {site['id']} (已存在，跳过)")
            continue
        src = build_magnet_source(site)
        filename = f"{site['id'].replace('builtin.', '')}.json"
        filepath = SOURCES_DIR / filename
        filepath.write_text(json.dumps(src, ensure_ascii=False, indent=2), encoding="utf-8")
        manifest_entries.append(f"    'assets/sources/{filename}',")
        print(f"  ✓ {filename}")

    # 生成网盘源（跳过 skip=True 的条目）
    for site in PAN_SOURCES:
        if site.get("skip"):
            print(f"  ⏭ {site['id']} (已存在，跳过)")
            continue
        src = build_pan_source(site)
        filename = f"{site['id'].replace('builtin.', '')}.json"
        filepath = SOURCES_DIR / filename
        filepath.write_text(json.dumps(src, ensure_ascii=False, indent=2), encoding="utf-8")
        manifest_entries.append(f"    'assets/sources/{filename}',")
        print(f"  ✓ {filename}")

    # 写入清单文件
    skipped_count = sum(1 for s in MAGNET_SOURCES if s.get("skip")) + sum(1 for s in PAN_SOURCES if s.get("skip"))
    new_count = len(MAGNET_SOURCES) + len(PAN_SOURCES) - skipped_count
    list_path = SOURCES_DIR.parent / "new_sources_list.txt"
    list_path.write_text(
        f"新增磁力源: {len(MAGNET_SOURCES) - skipped_count} 个（跳过 {skipped_count} 个已有精确源）\n"
        f"新增网盘源: {len(PAN_SOURCES) - skipped_count} 个\n"
        f"合计新增: {new_count} 个源文件\n\n"
        "请在 builtin_sources.dart 的 _manifest 数组中添加以下行：\n\n"
        + "\n".join(manifest_entries),
        encoding="utf-8"
    )
    print(f"\n✅ 共生成 {new_count} 个新源文件")
    print(f"   输出目录: {SOURCES_DIR}")
    print(f"   清单文件: {list_path}")


if __name__ == "__main__":
    main()
