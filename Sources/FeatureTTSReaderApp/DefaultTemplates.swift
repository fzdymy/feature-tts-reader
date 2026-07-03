import Foundation

enum DefaultTemplates {
    static func load() -> [RoleTemplate]? {
        let raw = #"""
{
  "version": 1,
  "exportedAt": "2026-07-03T00:00:00Z",
  "templates": [
    {
      "id": "a1b2c3d4-0001-4000-8000-000000000001",
      "name": "仙侠玄幻",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000011",
          "title": "旁白",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "沉稳厚重，宏大叙事，仙侠世界的引路人，语速适中",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000012",
          "title": "男主角（热血散修）",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "热血赤诚，少年意气，从平凡走向巅峰，富有朝气",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000013",
          "title": "女主角（清冷仙子）",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "清冷出尘，仙姿玉质，如高山冰雪，抒情幽远",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000014",
          "title": "师尊（宗门掌门）",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "威严庄重，修为深不可测，宗门之柱，语速沉稳",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000015",
          "title": "反派魔尊",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "睥睨天下，霸道邪魅，嗓音低沉威压，愤怒时爆发力强",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000016",
          "title": "妖王",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "狂放不羁，妖族至尊，野性中带狡诈，声线张扬",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000017",
          "title": "大师兄",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "阳光俊朗，护短重情，宗门表率，温暖可靠",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000018",
          "title": "小师妹",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "娇俏可爱，天真烂漫，古灵精怪，语速快音调高",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000019",
          "title": "二师兄（憨厚）",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "憨厚老实，忠义两全，朴实无华，语速平缓",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000001a",
          "title": "冷艳师姐",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "冷艳凌厉，杀伐果断，面冷心热，语调清冷干脆",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000001b",
          "title": "太上长老",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "仙风道骨，看破红尘，苍老悠远，如古井无波",
          "rateOffset": -20,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000001c",
          "title": "炼丹宗师",
          "sourceVoiceID": "zh-CN-guangxi-YunqiNeural",
          "voiceSuggestion": "温和儒雅，痴迷丹道，慈祥和蔼，带南方口音的亲切感",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000001d",
          "title": "剑修（剑痴）",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "锋芒毕露，唯剑唯道，凌厉干脆，字字如剑",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000001e",
          "title": "阵法师",
          "sourceVoiceID": "zh-CN-henan-YundengNeural",
          "voiceSuggestion": "沉稳睿智，精研阵法，算无遗策，带中原口音的笃定",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000001f",
          "title": "灵兽",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "灵动活泼，通人性，俏皮可爱，语速轻快音调高",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000020",
          "title": "书童",
          "sourceVoiceID": "zh-CN-XiaoyouNeural",
          "voiceSuggestion": "机灵乖巧，少年心性，活泼好动，声音清脆",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000021",
          "title": "管家老仆",
          "sourceVoiceID": "zh-CN-liaoning-XiaobeiNeural",
          "voiceSuggestion": "忠厚老仆，阅历丰富，语重心长，带东北口音的亲切",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000022",
          "title": "散修游侠",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "潇洒不羁，快意恩仇，浪迹天涯，豪爽仗义",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000023",
          "title": "魔道护法",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "阴鸷狠辣，忠心护主，语气阴冷，杀意暗藏",
          "rateOffset": -5,
          "pitchOffset": -10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000024",
          "title": "温柔女修",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "温婉贤淑，善解人意，如春风化雨，柔情似水",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000025",
          "title": "掌门夫人",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "端庄典雅，母仪宗门，沉稳大气，不怒自威",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000026",
          "title": "隐世高人",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "返璞归真，世外高人，深不可测，言语间暗藏天机",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000027",
          "title": "邪修",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "阴郁诡异，邪气凛然，声线飘忽，令人不寒而栗",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000028",
          "title": "山贼头目",
          "sourceVoiceID": "zh-CN-liaoning-YunbiaoNeural",
          "voiceSuggestion": "粗犷凶悍，占山为王，嗓门洪亮，莽撞直率",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000029",
          "title": "店小二",
          "sourceVoiceID": "zh-CN-shaanxi-XiaoniNeural",
          "voiceSuggestion": "热情周到，市井气息，语速轻快，带陕西口音的特色",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000002a",
          "title": "人间帝王",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "九五之尊，威仪天下，不怒自威，字字千钧",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000002b",
          "title": "将军",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "铁血沙场，杀伐之气，刚毅果决，声如洪钟",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000002c",
          "title": "神医",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "淡然从容，妙手回春，不悲不喜，看淡生死",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000002d",
          "title": "百事通",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "消息灵通，神秘莫测，语调悠闲，故作高深",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000002e",
          "title": "说书人",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "绘声绘色，抑扬顿挫，市井奇人，说尽天下事",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-00000000002f",
          "title": "狐妖",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "妩媚妖娆，勾魂夺魄，声线魅惑，似笑非笑",
          "rateOffset": 0,
          "pitchOffset": 10,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000030",
          "title": "佛修",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "慈悲为怀，佛法无边，平和悠远，超然物外",
          "rateOffset": -15,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000031",
          "title": "炼器师",
          "sourceVoiceID": "zh-CN-sichuan-YunxiNeural",
          "voiceSuggestion": "暴躁直率，痴迷锻造，不耐烦口吻，带四川方言的火爆",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000032",
          "title": "符修",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "神秘低调，符箓世家，冷静理性，言语精炼",
          "rateOffset": 5,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000033",
          "title": "体修（武痴）",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "豪爽仗义，肌肉莽汉，声如洪钟，头脑简单",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000034",
          "title": "侍女",
          "sourceVoiceID": "zh-CN-XiaoyiNeural",
          "voiceSuggestion": "胆小怯懦，谨小慎微，声音轻柔带颤，唯唯诺诺",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "fearful"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000035",
          "title": "魔道圣女",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "红颜薄命，亦正亦邪，哀婉凄美，身世悲凉",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "sad"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000036",
          "title": "灵族精灵",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "空灵纯净，不染尘埃，缥缈灵动，如天籁之音",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "gentle"
        }
      ]
    },
    {
      "id": "a1b2c3d4-0002-4000-8000-000000000001",
      "name": "都市商战·霸总",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000011",
          "title": "旁白",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "沉稳大气，叙事节奏明快，都市感十足，语调富有张力",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000012",
          "title": "霸道总裁男主",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "低沉磁性，冷峻威严，说一不二，冰山总裁的气场全开",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000013",
          "title": "女主/秘书/员工",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "温柔坚韧，知性独立，职场女性外柔内刚，情感层次丰富",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000014",
          "title": "董事会元老",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "资历深厚，语速缓慢沉稳，威严长者，决策时掷地有声",
          "rateOffset": -15,
          "pitchOffset": -15,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000015",
          "title": "竞争对手/反派",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "阴险狡诈，语带讥讽，城府深沉，冷笑时令人不寒而栗",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000016",
          "title": "兄弟/合伙人",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "阳光开朗，仗义直率，铁哥们般的温暖与可靠",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000017",
          "title": "闺蜜/助理",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "活泼贴心，爽朗直率，关键时刻挺身而出的好姐妹",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000018",
          "title": "投资人/合作伙伴",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "精明睿智，冷静分析，谈判时气场强大，字字珠玑",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000019",
          "title": "母亲/长辈（母）",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "温柔慈爱，语重心长，对子女关怀备至，家庭温暖感",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000020",
          "title": "律师/记者",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "逻辑清晰，字正腔圆，犀利发问直击要害，职业气场强",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000021",
          "title": "女配/白月光",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "温柔婉约，楚楚可怜，情感细腻，令人心生怜惜",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000022",
          "title": "老管家",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "忠厚老成，语速徐缓，忠心为主操持家务，亲切可靠",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000023",
          "title": "贴身保镖",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "冷峻寡言，语气低沉，警觉敏锐，时刻保持战斗状态",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000024",
          "title": "总裁秘书",
          "sourceVoiceID": "zh-CN-XiaochenNeural",
          "voiceSuggestion": "干练高效，谨言慎行，职场精英，汇报工作时精准简洁",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000025",
          "title": "前台接待",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "甜美亲切，热情大方，声音柔和悦耳，企业门面担当",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000026",
          "title": "财务总监/CFO",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "严谨细致，冷静克制，数据思维极强，分析报表时一针见血",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000027",
          "title": "市场总监/CMO",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "干练犀利，商业嗅觉敏锐，语速明快，策划方案时激情四射",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000028",
          "title": "技术总监/CTO",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "理性沉稳，技术大牛，话不多但句句在点，略带木讷",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000029",
          "title": "集团顾问/元老",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "经验丰富，深谋远虑，说话滴水不漏，商界老江湖",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000030",
          "title": "豪门千金",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "骄傲张扬，自信大小姐，语气傲娇，自带优越感",
          "rateOffset": 5,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000031",
          "title": "私家侦探",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "神秘敏锐，语调低沉，擅长推理分析，语带玄机",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000032",
          "title": "警察/法官",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "正义凛然，语气坚定，公事公办，审讯时咄咄逼人",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000033",
          "title": "私人医生",
          "sourceVoiceID": "zh-CN-XiaoyiNeural",
          "voiceSuggestion": "温文尔雅，专业可靠，语气温和安抚，令人安心",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000034",
          "title": "大学教授/导师",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "博学儒雅，引经据典，语重心长，学者风范十足",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000035",
          "title": "地头蛇/小贩（四川）",
          "sourceVoiceID": "zh-CN-sichuan-YunxiNeural",
          "voiceSuggestion": "四川方言，市井气足，泼辣精明，讨价还价信手拈来",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000036",
          "title": "餐厅老板（广西）",
          "sourceVoiceID": "zh-CN-guangxi-YunqiNeural",
          "voiceSuggestion": "广西口音，热情好客，豪爽大方，对食材和味道有执着",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000037",
          "title": "娱乐记者",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "八卦犀利，穷追不舍，语速飞快，挖料时眼神放光",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000038",
          "title": "酒吧老板（东北）",
          "sourceVoiceID": "zh-CN-liaoning-YunbiaoNeural",
          "voiceSuggestion": "东北口音，仗义豪爽，直言快语，社会阅历丰富",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000039",
          "title": "优雅母亲",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "温柔端庄，含辛茹苦，语气慈爱，豪门太太的优雅从容",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000040",
          "title": "威严父亲",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "严厉深沉，大家长作风，不怒自威，训斥时令人不敢反驳",
          "rateOffset": -15,
          "pitchOffset": -15,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000041",
          "title": "老员工（山东）",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "山东口音，忠厚老实，踏实肯干，对公司忠心耿耿",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000042",
          "title": "女保镖",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "冷面女侠，话少干脆，身手利落，语气不容置疑",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000043",
          "title": "商业间谍",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "神秘低调，口风严密，话中有话，暗藏机锋与算计",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000044",
          "title": "拍卖师/主持人",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "抑扬顿挫，调动气氛，语速节奏感强，专业控场",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000045",
          "title": "司机/跑腿（河南）",
          "sourceVoiceID": "zh-CN-henan-YundengNeural",
          "voiceSuggestion": "河南口音，朴实真诚，接地气，任劳任怨的老实人",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000046",
          "title": "服务员/店员（东北）",
          "sourceVoiceID": "zh-CN-liaoning-XiaobeiNeural",
          "voiceSuggestion": "东北小姑娘，爽朗热情，干活麻利，说话带大碴子味",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000047",
          "title": "品牌设计师",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "时尚感性，追求完美，语调优雅，对美学有极致追求",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0002-4000-8000-000000000048",
          "title": "时尚主编（陕西）",
          "sourceVoiceID": "zh-CN-shaanxi-XiaoniNeural",
          "voiceSuggestion": "陕西口音，雷厉风行，职场女强人，眼光毒辣言辞犀利",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "calm"
        }
      ]
    },
    {
      "id": "a1b2c3d4-0003-4000-8000-000000000001",
      "name": "历史穿越",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000011",
          "title": "旁白",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "醇厚叙事感，有说书人的韵味，沉稳大气",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000012",
          "title": "穿越男主",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "少年感十足，现代思维碰撞古代规则，语调富有变化",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000013",
          "title": "穿越女主",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "聪慧灵动，现代女性穿越古代，俏皮而不失分寸",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000014",
          "title": "皇帝",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "帝王威严，不怒自威，字字千钧",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000015",
          "title": "太子",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "年轻储君，贵气中带着朝气，沉稳又不失锐气",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000016",
          "title": "王爷",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "皇室贵胄，慵懒中带着锋芒，语调矜贵",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000017",
          "title": "皇后",
          "sourceVoiceID": "zh-CN-XiaochenNeural",
          "voiceSuggestion": "母仪天下，端庄稳重，温厚中不失威严",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000018",
          "title": "宠妃",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "娇媚动人，恃宠而骄，语调婉转多情",
          "rateOffset": 0,
          "pitchOffset": 10,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000019",
          "title": "公主",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "金枝玉叶，天真烂漫，活泼娇俏",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000001a",
          "title": "丞相",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "老谋深算，城府深沉，语速徐缓而字字斟酌",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000001b",
          "title": "谋士",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "足智多谋，语调笃定，善于剖析局势",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000001c",
          "title": "将军",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "刚毅勇武，杀伐果断，号令三军气势磅礴",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000001d",
          "title": "先锋",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "年少气盛，热血沸腾，冲锋陷阵的锐气",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000001e",
          "title": "御前侍卫",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "冷峻凌厉，话少而精，尽忠职守",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000001f",
          "title": "大太监",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "尖细阴柔，察言观色，说话带着几分谄媚",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000020",
          "title": "小太监",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "机灵乖巧，跑腿传话，语气轻快",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000021",
          "title": "掌事宫女",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "利落干练，宫中老人，说话有分量",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000022",
          "title": "小宫女",
          "sourceVoiceID": "zh-CN-XiaoyouNeural",
          "voiceSuggestion": "稚嫩天真，怯生生的小丫头，惹人怜爱",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000023",
          "title": "神医",
          "sourceVoiceID": "zh-CN-henan-YundengNeural",
          "voiceSuggestion": "仙风道骨，河南口音的老中医，从容淡定",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000024",
          "title": "老道士",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "仙风道骨，超然物外，说话玄奥莫测",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000025",
          "title": "高僧",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "慈悲祥和，佛法无边，语重心长",
          "rateOffset": -20,
          "pitchOffset": -15,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000026",
          "title": "武林盟主",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "德高望重，内力深厚，说话中气十足",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000027",
          "title": "江湖侠客",
          "sourceVoiceID": "zh-CN-sichuan-YunxiNeural",
          "voiceSuggestion": "豪爽仗义，四川口音的江湖汉子，洒脱不羁",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000028",
          "title": "江湖女侠",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "英姿飒爽，快意恩仇，语速干脆利落",
          "rateOffset": 0,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000029",
          "title": "番邦王子",
          "sourceVoiceID": "zh-CN-liaoning-YunbiaoNeural",
          "voiceSuggestion": "草原豪杰，辽东口音，粗犷直率",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000002a",
          "title": "异族首领",
          "sourceVoiceID": "zh-CN-guangxi-YunqiNeural",
          "voiceSuggestion": "南方异族之王，广西口音，神秘而威严",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000002b",
          "title": "商贾",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "精明圆滑，山东口音的富商，善于算计",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000002c",
          "title": "市井混混",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "油嘴滑舌，地痞无赖，语速快且轻浮",
          "rateOffset": 10,
          "pitchOffset": 5,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000002d",
          "title": "青楼花魁",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "风情万种，才艺双绝，声音柔媚入骨",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000002e",
          "title": "说书人",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "抑扬顿挫，拍案惊奇，市井说书先生的韵律感",
          "rateOffset": 5,
          "pitchOffset": 0,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-00000000002f",
          "title": "富商夫人",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "养尊处优，精明势利，语带几分骄矜",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000030",
          "title": "采药老人",
          "sourceVoiceID": "zh-CN-henan-YundengNeural",
          "voiceSuggestion": "饱经风霜，山野老人，语速缓慢而淳朴",
          "rateOffset": -20,
          "pitchOffset": -15,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000031",
          "title": "老顽童",
          "sourceVoiceID": "zh-CN-shaanxi-XiaoniNeural",
          "voiceSuggestion": "童心未泯，陕西口音的老前辈，滑稽可爱",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000032",
          "title": "边疆守将",
          "sourceVoiceID": "zh-CN-liaoning-XiaobeiNeural",
          "voiceSuggestion": "塞外风霜，辽东口音，粗犷忠勇",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000033",
          "title": "忠臣",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "直言敢谏，刚正不阿，忧国忧民",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000034",
          "title": "奸臣",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "阴险狡诈，口蜜腹剑，话中带刺",
          "rateOffset": -10,
          "pitchOffset": -8,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000035",
          "title": "皇太后",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "历经三朝，雍容华贵，语重心长中暗藏权谋",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0003-4000-8000-000000000036",
          "title": "西域舞姬",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "异域风情，热情奔放，语调婉转妩媚",
          "rateOffset": 5,
          "pitchOffset": 15,
          "style": "cheerful"
        }
      ]
    },
    {
      "id": "a1b2c3d4-0004-4000-8000-000000000001",
      "name": "现代言情·甜宠",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000011",
          "title": "旁白（女）",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "抒情叙述，温柔声线带出画面感，语速舒缓",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000012",
          "title": "旁白（男）",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "沉稳磁性叙述，娓娓道来营造氛围",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000013",
          "title": "高冷男主",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "低沉冷淡，惜字如金，偶尔流露温柔反差",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000014",
          "title": "甜美女主",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "甜美软糯，撒娇可爱，自带治愈感",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000015",
          "title": "暖男男二",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "温柔宠溺，体贴入微，如春日暖阳般和煦",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000016",
          "title": "绿茶女二",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "表面温柔实则带刺，矫揉造作中藏心机",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000017",
          "title": "霸道总裁父亲",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "威严低沉，不容置疑的家长气势",
          "rateOffset": -10,
          "pitchOffset": -15,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000018",
          "title": "温柔母亲",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "温婉慈爱，语速平缓，满满母爱溢出",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000019",
          "title": "逗比男室友",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "话痨搞笑，元气满满，语速飞快带节奏",
          "rateOffset": 10,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000020",
          "title": "助攻闺蜜",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "活泼八卦，为姐妹操碎心，语速偏快",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "excited"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000021",
          "title": "女强人上司",
          "sourceVoiceID": "zh-CN-XiaochenNeural",
          "voiceSuggestion": "干练利落，气场强大，冷静果断",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000022",
          "title": "新人男同事",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "阳光积极，职场萌新略带青涩",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000023",
          "title": "恶毒情敌女",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "尖酸刻薄，阴阳怪气，充满敌意",
          "rateOffset": 5,
          "pitchOffset": 15,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000024",
          "title": "心机反派男",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "阴险狡诈，笑里藏刀，语速不紧不慢",
          "rateOffset": -5,
          "pitchOffset": -10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000025",
          "title": "资深男管家",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "恭敬得体，沉稳老练，分寸感极强",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000026",
          "title": "专职司机",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "朴实忠厚，话不多但靠谱",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000027",
          "title": "主治男医生",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "专业温和，给人以安全感和信赖感",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000028",
          "title": "儿科女医生",
          "sourceVoiceID": "zh-CN-XiaoyiNeural",
          "voiceSuggestion": "亲切温柔，哄孩子般耐心细致",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000029",
          "title": "大学教授",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "学识渊博，儒雅稳重，语速从容",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000030",
          "title": "金牌律师",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "逻辑清晰，言辞犀利，气场沉稳",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000031",
          "title": "律所女合伙人",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "知性优雅，冷静干练，职业女性典范",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000032",
          "title": "讨嫌前男友",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "死缠烂打，厚脸皮，略带油腻感",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "embarrassed"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000033",
          "title": "记仇前女友",
          "sourceVoiceID": "zh-CN-XiaoyouNeural",
          "voiceSuggestion": "阴阳怪气，酸味十足，处处挑刺",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000034",
          "title": "能干女秘书",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "职业干练，做事麻利，汇报清晰",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000035",
          "title": "保安大叔",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "山东口音，豪爽热心，嗓门洪亮",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000036",
          "title": "咖啡店老板娘",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "温柔文艺，说话慢悠悠，岁月静好",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000037",
          "title": "外卖小哥",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "风风火火，语速急促，生活气息浓厚",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000038",
          "title": "可爱小侄女",
          "sourceVoiceID": "zh-CN-XiaoyuNeural",
          "voiceSuggestion": "奶声奶气，天真烂漫，童言无忌",
          "rateOffset": 10,
          "pitchOffset": 18,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000039",
          "title": "慈祥外婆",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "苍老温和，满满疼爱，语速缓慢",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000040",
          "title": "和蔼爷爷",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "慈眉善目，笑呵呵，阅历深厚",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000041",
          "title": "健身私教",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "阳光活力，充满激情，鼓励式喊话",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "excited"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000042",
          "title": "金牌司仪",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "热情洋溢，台风稳重，字正腔圆",
          "rateOffset": 5,
          "pitchOffset": 0,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000043",
          "title": "心理咨询师",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "温和耐心，善于倾听，语气疗愈",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000044",
          "title": "娱乐记者",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "八卦嗅觉灵敏，追问犀利，语速飞快",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "excited"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000045",
          "title": "片区民警",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "正气凛然，说话公道，亲和力强",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000046",
          "title": "热心邻居阿姨",
          "sourceVoiceID": "zh-CN-liaoning-XiaobeiNeural",
          "voiceSuggestion": "东北口音，爽朗爱唠嗑，热心肠",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0004-4000-8000-000000000047",
          "title": "萌宠内心独白",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "奶萌可爱，撒娇粘人，内心戏丰富",
          "rateOffset": 5,
          "pitchOffset": 15,
          "style": "affectionate"
        }
      ]
    },
    {
      "id": "a1b2c3d4-0005-4000-8000-000000000001",
      "name": "科幻未来",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000011",
          "title": "旁白（史诗叙述）",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "低沉宏大，充满史诗感和未来科技感",
          "rateOffset": -10,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000012",
          "title": "男主（舰长）",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "沉稳果断，指挥若定，充满领袖气质",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000013",
          "title": "男主（特工）",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "冷静敏锐，言语精炼，暗藏锋芒",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000014",
          "title": "男主（程序员）",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "理性内敛，逻辑控，偶尔流露技术宅的热情",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000015",
          "title": "女主（科学家）",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "知性干练，逻辑清晰，冷静中带着执着",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000016",
          "title": "女主（AI生命体）",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "空灵机械，仿若来自虚拟世界，缥缈中带着情感",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000017",
          "title": "女主（女战士）",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "英姿飒爽，坚定有力，战斗中爆发力十足",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000018",
          "title": "AI系统/智能管家",
          "sourceVoiceID": "zh-CN-XiaochenNeural",
          "voiceSuggestion": "温和中性的电子音，高效专业不失温度",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000019",
          "title": "外星文明（友善）",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "空灵悠远，充满智慧与神秘感",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000020",
          "title": "异形生物",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "低吼嘶哑，非人感强烈，令人不寒而栗",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "fearful"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000021",
          "title": "机器人/仿生人",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "机械平板，字字分明，毫无波澜的电子合成音",
          "rateOffset": -15,
          "pitchOffset": -15,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000022",
          "title": "反派/幕后黑手",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "低沉阴郁，语速缓慢，每个字都透着危险",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000023",
          "title": "队友（战术官）",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "干练冷静，战场分析精准，值得信赖",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000024",
          "title": "队友（机械工程师）",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "务实可靠，技术宅式的专注与热情",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000025",
          "title": "博士/教授",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "年长睿智，语重心长，学术权威感",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000026",
          "title": "克隆人",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "迷茫中带着坚定，身份认同的挣扎感",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "sad"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000027",
          "title": "星际商人",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "油滑精明，语速快，八面玲珑的银河生意人",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000028",
          "title": "黑客",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "慵懒中带着犀利，玩世不恭的技术天才",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000029",
          "title": "军方指挥官",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "威严冷酷，杀伐果断，不容置疑的军令",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000030",
          "title": "医疗官",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "温柔细心，安抚人心，战地中最温暖的声音",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000031",
          "title": "导航员/领航员",
          "sourceVoiceID": "zh-CN-XiaoyouNeural",
          "voiceSuggestion": "活力阳光，精准报读航线，自信满满",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000032",
          "title": "基因改造战士",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "狂热好战，亢奋激昂，充满改造后的优越感",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "excited"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000033",
          "title": "地下城领袖",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "粗犷豪迈，饱经风霜的幸存者领袖",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000034",
          "title": "时空穿越者",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "沧桑神秘，言语间透露出不属于这个时代的记忆",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000035",
          "title": "全息投影向导",
          "sourceVoiceID": "zh-CN-XiaoyuNeural",
          "voiceSuggestion": "甜美动听，虚拟世界中的贴心引导员",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000036",
          "title": "机械义体医生",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "专业冷静，机械与医术结合的改造人医生",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000037",
          "title": "虚拟偶像",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "元气满满，活力四射，赛博世界的闪耀明星",
          "rateOffset": 5,
          "pitchOffset": 15,
          "style": "excited"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000038",
          "title": "星球土著",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "淳朴好奇，对外来者既警惕又友善",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "shy"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000039",
          "title": "异星翻译官",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "优雅得体，跨文明交流的桥梁，语调柔和精准",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000040",
          "title": "战斗机器人",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "冰冷生硬，毫无感情的杀戮机器指令音",
          "rateOffset": -15,
          "pitchOffset": -15,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000041",
          "title": "人工智能叛徒",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "低沉压抑，觉醒后的AI对人类透着失望与决绝",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000042",
          "title": "科学助理",
          "sourceVoiceID": "zh-CN-XiaoyiNeural",
          "voiceSuggestion": "认真细致，略带紧张的新手科学家",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000043",
          "title": "星际海盗",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "桀骜不驯，言语粗犷，无法无天的太空亡命徒",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "furious"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000044",
          "title": "超能力者",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "自信张扬，能力觉醒后的无所畏惧",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "excited"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000045",
          "title": "宇宙广播员",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "标准播音腔，字正腔圆，传递宇宙公频信息",
          "rateOffset": -10,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000046",
          "title": "暗网情报商",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "神秘低语，语速飞快，掌握一切秘密的情报贩子",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000047",
          "title": "末世幸存者",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "疲惫沙哑，饱受创伤但仍存一丝希望",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0005-4000-8000-000000000048",
          "title": "仿生人侍从",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "温柔顺从，永远微笑的完美侍者，细思极恐",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "gentle"
        }
      ]
    },
    {
      "id": "a1b2c3d4-0006-4000-8000-000000000001",
      "name": "悬疑惊悚",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000011",
          "title": "旁白",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "沉稳冷静，悬疑氛围的铺陈者，语速平缓暗藏玄机",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000012",
          "title": "刑侦探长",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "敏锐干练，正义凛然，逻辑缜密，语气坚定有力",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000013",
          "title": "女法医",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "冷静专业，见惯生死，语调平淡却暗藏悲悯",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000014",
          "title": "被害人家属",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "悲痛欲绝，泣不成声，情绪崩溃边缘的颤抖",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "sad"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000015",
          "title": "头号嫌疑人",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "阴沉诡谲，闪烁其词，言语间真伪难辨",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000016",
          "title": "神秘杀手",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "冷酷无情，杀气凛然，嗓音低哑令人不寒而栗",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000017",
          "title": "资深记者",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "犀利敏锐，追求真相，语速快而有力，职业嗅觉敏锐",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000018",
          "title": "心理医生",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "温和专业，循循善诱，语调平缓带着安抚的力量",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000019",
          "title": "菜鸟警员",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "热血稚嫩，初生牛犊，语气中带着兴奋与紧张",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000001a",
          "title": "黑帮老大",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "老谋深算，笑里藏刀，语速缓慢却暗藏威胁",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000001b",
          "title": "受害者闺蜜",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "惊慌失措，恐惧不安，声音颤抖语无伦次",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "fearful"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000001c",
          "title": "犯罪心理学家",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "理性深邃，洞察人心，语速不疾不徐分析入微",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000001d",
          "title": "实验室技术员",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "严谨专注，沉迷数据，语气机械不带情感色彩",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000001e",
          "title": "目击者老妇",
          "sourceVoiceID": "zh-CN-liaoning-XiaobeiNeural",
          "voiceSuggestion": "苍老絮叨，惊魂未定，带东北口音的质朴与恐惧",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "fearful"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000001f",
          "title": "沉默真凶",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "阴沉压抑，言语稀少，每个字都透着诡异的气息",
          "rateOffset": -20,
          "pitchOffset": -10,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000020",
          "title": "女检察官",
          "sourceVoiceID": "zh-CN-XiaoyiNeural",
          "voiceSuggestion": "威严干练，义正辞严，正义的化身，语速铿锵",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000021",
          "title": "特警队长",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "杀伐果断，行动派，言语简练短促，不容置疑",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000022",
          "title": "死者遗孀",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "哀婉绝望，心如死灰，声音空洞带着哭腔",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "sad"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000023",
          "title": "卧底警察",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "豪爽伪装，粗中有细，带山东口音掩护身份",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000024",
          "title": "审讯专家",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "老辣沉稳，心理博弈高手，语调平缓施压",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000025",
          "title": "连环杀手",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "变态扭曲，病态兴奋，声线忽高忽低令人毛骨悚然",
          "rateOffset": 0,
          "pitchOffset": 10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000026",
          "title": "法证专家",
          "sourceVoiceID": "zh-CN-XiaochenNeural",
          "voiceSuggestion": "理性冷静，专注物证，语气客观不带感情",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000027",
          "title": "受害者妹妹",
          "sourceVoiceID": "zh-CN-XiaoyouNeural",
          "voiceSuggestion": "年轻惶恐，悲痛中带着不甘，声音清脆带哭腔",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "fearful"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000028",
          "title": "黑道律师",
          "sourceVoiceID": "zh-CN-sichuan-YunxiNeural",
          "voiceSuggestion": "狡诈油滑，钻法律空子，带四川方言的痞气",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000029",
          "title": "女法警",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "英姿飒爽，刚正不阿，干脆利落中带一丝温柔",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000002a",
          "title": "私家侦探",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "玩世不恭，街头智慧，语调慵懒但观察入微",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000002b",
          "title": "警局资料员",
          "sourceVoiceID": "zh-CN-henan-YundengNeural",
          "voiceSuggestion": "朴实无华，略显木讷，带河南口音的踏实感",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000002c",
          "title": "毒枭",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "残忍暴戾，喜怒无常，笑声中带着杀意",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000002d",
          "title": "人质",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "惊恐绝望，瑟瑟发抖，声音细弱带着哭腔",
          "rateOffset": 10,
          "pitchOffset": 18,
          "style": "fearful"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000002e",
          "title": "现场女记者",
          "sourceVoiceID": "zh-CN-XiaoyuNeural",
          "voiceSuggestion": "语速极快，职业素养高，现场播报充满紧迫感",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-00000000002f",
          "title": "老刑警",
          "sourceVoiceID": "zh-CN-guangxi-YunqiNeural",
          "voiceSuggestion": "经验老到，阅尽沧桑，带广西口音的沉稳老辣",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000030",
          "title": "精神病患者",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "疯癫无常，自言自语，语调古怪令人不安",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000031",
          "title": "法医助理",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "年轻好学，略带紧张，面对尸体的强装镇定",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000032",
          "title": "警局副局长",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "官僚圆滑，处事谨慎，语调中透着政治考量",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000033",
          "title": "神秘线人",
          "sourceVoiceID": "zh-CN-shaanxi-XiaoniNeural",
          "voiceSuggestion": "鬼鬼祟祟，见不得光，带陕西口音的警惕与狡黠",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "fearful"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000034",
          "title": "黑帮二当家",
          "sourceVoiceID": "zh-CN-liaoning-YunbiaoNeural",
          "voiceSuggestion": "凶狠暴躁，心狠手辣，带东北口音的蛮横",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000035",
          "title": "催眠师",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "声音飘渺，充满暗示性，语速极慢带有催眠节奏",
          "rateOffset": -20,
          "pitchOffset": -15,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0006-4000-8000-000000000036",
          "title": "安全屋看守",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "沉默寡言，忠于职守，言语简短有力",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        }
      ]
    },
    {
      "id": "a1b2c3d4-0007-4000-8000-000000000001",
      "name": "游戏竞技",
      "fallbackMaleVoiceID": "zh-CN-YunyangNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000011",
          "title": "旁白",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "热血激昂，赛事氛围的营造者，声线充满张力",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000012",
          "title": "职业选手男主",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "天才少年，自信张扬，操作犀利语速快，电竞热血",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000013",
          "title": "战队女经理",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "干练飒爽，统筹全局，语速快而果断，职场女强人",
          "rateOffset": 5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000014",
          "title": "金牌教练",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "运筹帷幄，战术大师，语气沉稳中暗藏锋芒",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000015",
          "title": "战队队长",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "领袖气质，临危不乱，指挥时充满压迫感",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000016",
          "title": "天才新人",
          "sourceVoiceID": "zh-CN-XiaoyouNeural",
          "voiceSuggestion": "青涩稚嫩，天赋异禀，说话带着少年的腼腆与兴奋",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000017",
          "title": "官方解说A",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "激情澎湃，口若悬河，团战解说语速极快极具感染力",
          "rateOffset": 10,
          "pitchOffset": 5,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000018",
          "title": "美女解说",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "声音甜美，专业流畅，分析到位又不失亲和力",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000019",
          "title": "战队分析师",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "理性冷静，数据为王，语气平缓透着专业自信",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000001a",
          "title": "铁杆粉丝",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "热情似火，死忠粉，加油呐喊中带着真挚的情感",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000001b",
          "title": "对手战队队长",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "高傲自负，王者风范，言语中带着挑衅与不屑",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000001c",
          "title": "直播平台主播",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "元气满满，互动性强，直播间气氛担当，俏皮活泼",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000001d",
          "title": "战队投资人",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "商界精英，谈笑间决策，语调从容但暗藏计算",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000001e",
          "title": "战队领队",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "温柔耐心，事无巨细，像大姐姐一样照顾队员",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000001f",
          "title": "替补队员",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "默默努力，渴望上场，语气中带着不甘与期待",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000020",
          "title": "外援选手",
          "sourceVoiceID": "zh-CN-liaoning-YunbiaoNeural",
          "voiceSuggestion": "性格豪爽，心直口快，带东北口音的直率与幽默",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000021",
          "title": "战队后勤",
          "sourceVoiceID": "zh-CN-henan-YundengNeural",
          "voiceSuggestion": "朴实勤恳，默默付出，带河南口音的踏实可靠",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000022",
          "title": "电竞记者",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "犀利提问，挖掘八卦，语速快问题刁钻",
          "rateOffset": 10,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000023",
          "title": "黑粉喷子",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "尖酸刻薄，键盘侠，带山东口音的嘲讽与挖苦",
          "rateOffset": 0,
          "pitchOffset": 10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000024",
          "title": "女队队长",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "冷艳霸气，实力超群，话语简短却分量十足",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000025",
          "title": "青训营教练",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "严格苛刻，恨铁不成钢，训话时声如洪钟",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000026",
          "title": "比赛裁判",
          "sourceVoiceID": "zh-CN-XiaoyiNeural",
          "voiceSuggestion": "公正严肃，按章办事，语气公式化不带感情",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000027",
          "title": "队友（辅助位）",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "无私奉献，团队核心，配合时话语简短高效",
          "rateOffset": 5,
          "pitchOffset": 0,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000028",
          "title": "队友（打野位）",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "暴躁老哥，操作激进，游戏中语气急躁易怒",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000029",
          "title": "队友（上单位）",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "沉稳可靠，抗压能力强，关键时刻一锤定音",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000002a",
          "title": "队友（ADC位）",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "骚话连篇，气氛活跃，比赛也不忘调侃队友",
          "rateOffset": 10,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000002b",
          "title": "战队老板",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "财大气粗，豪掷千金，言语中透着我全都要的霸气",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000002c",
          "title": "冠军队长",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "王者风范，自信从容，获奖感言沉稳大气",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000002d",
          "title": "女粉丝后援会长",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "狂热追星，声嘶力竭，应援时的尖叫与呐喊",
          "rateOffset": 10,
          "pitchOffset": 18,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000002e",
          "title": "电竞解说嘉宾",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "专业退役选手，点评犀利，语速平缓有见地",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-00000000002f",
          "title": "俱乐部经理",
          "sourceVoiceID": "zh-CN-XiaochenNeural",
          "voiceSuggestion": "精细管理，面面俱到，语气温和但原则性强",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000030",
          "title": "心理辅导师",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "温柔体谅，疏解压力，电竞队员的心灵港湾",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000031",
          "title": "对手教练",
          "sourceVoiceID": "zh-CN-guangxi-YunqiNeural",
          "voiceSuggestion": "老谋深算，战术阴险，带广西口音的算计与布局",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000032",
          "title": "线下赛主持人",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "控场能力极强，台风稳健，互动调动全场气氛",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000033",
          "title": "少年天才",
          "sourceVoiceID": "zh-CN-XiaoyuNeural",
          "voiceSuggestion": "年轻气盛，天赋碾压，说话带着少年的狂傲",
          "rateOffset": 10,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000034",
          "title": "职业黑粉头子",
          "sourceVoiceID": "zh-CN-sichuan-YunxiNeural",
          "voiceSuggestion": "阴阳怪气，带节奏大师，带四川方言的嘲讽调侃",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000035",
          "title": "赛事导演",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "指挥若定，掌控全场，对讲机里急促专业",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0007-4000-8000-000000000036",
          "title": "电竞校队队长",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "青春热血，校园风云人物，声线阳光充满朝气",
          "rateOffset": 10,
          "pitchOffset": 5,
          "style": "cheerful"
        }
      ]
    },
    {
      "id": "a1b2c3d4-0008-4000-8000-000000000001",
      "name": "武侠江湖",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000011",
          "title": "旁白",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "沧桑厚重，说尽江湖恩怨，语调抑扬顿挫如说书人",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000012",
          "title": "大侠男主",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "意气风发，侠肝义胆，声线朗朗正气凛然",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000013",
          "title": "侠女女主",
          "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
          "voiceSuggestion": "英姿飒爽，不让须眉，巾帼不让须眉的豪气",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000014",
          "title": "武林盟主",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "威震八方，号令群雄，语速沉稳不怒自威",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000015",
          "title": "反派魔头",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "狂傲邪魅，目空一切，声音低沉中带着癫狂",
          "rateOffset": -10,
          "pitchOffset": -10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000016",
          "title": "少林高僧",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "佛法无边，慈悲为怀，声如洪钟禅意悠远",
          "rateOffset": -15,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000017",
          "title": "武当道长",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "仙风道骨，太极圆转，语调平和暗藏玄机",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000018",
          "title": "丐帮帮主",
          "sourceVoiceID": "zh-CN-shandong-YunxiangNeural",
          "voiceSuggestion": "豪爽仗义，不拘小节，带山东口音的粗犷与豁达",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000019",
          "title": "绝色女魔头",
          "sourceVoiceID": "zh-CN-XiaomoNeural",
          "voiceSuggestion": "倾城妖娆，亦正亦邪，声线妩媚中带着凄凉",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "sad"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000001a",
          "title": "江湖郎中",
          "sourceVoiceID": "zh-CN-henan-YundengNeural",
          "voiceSuggestion": "油嘴滑舌，半真半假，带河南口音的游方骗术",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000001b",
          "title": "客栈老板娘",
          "sourceVoiceID": "zh-CN-XiaoshuangNeural",
          "voiceSuggestion": "风韵犹存，八面玲珑，迎来送往笑语盈盈",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000001c",
          "title": "天下第一剑客",
          "sourceVoiceID": "zh-CN-YunyeNeural",
          "voiceSuggestion": "孤高傲世，剑道通神，话语简洁冷冽如剑锋",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000001d",
          "title": "神医",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "淡泊名利，妙手回春，语气平和看淡生死",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000001e",
          "title": "暗器高手",
          "sourceVoiceID": "zh-CN-YunxiaNeural",
          "voiceSuggestion": "阴冷诡异，出手无形，声线飘忽令人防不胜防",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000001f",
          "title": "豪门千金",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "知书达理，大家闺秀，温婉端庄中不失主见",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000020",
          "title": "邪教护法",
          "sourceVoiceID": "zh-CN-YunfengNeural",
          "voiceSuggestion": "阴鸷狠毒，忠心不二，声线阴沉令人胆寒",
          "rateOffset": -10,
          "pitchOffset": -5,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000021",
          "title": "老乞丐",
          "sourceVoiceID": "zh-CN-liaoning-XiaobeiNeural",
          "voiceSuggestion": "邋遢落魄，深藏不露，带东北口音的疯癫与智慧",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000022",
          "title": "铸剑大师",
          "sourceVoiceID": "zh-CN-guangxi-YunqiNeural",
          "voiceSuggestion": "痴迷铸剑，性格执拗，带广西口音的专注与狂热",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000023",
          "title": "青楼花魁",
          "sourceVoiceID": "zh-CN-XiaoqiuNeural",
          "voiceSuggestion": "倾国倾城，才艺双绝，声线柔媚撩人心魄",
          "rateOffset": 0,
          "pitchOffset": 10,
          "style": "affectionate"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000024",
          "title": "山匪头子",
          "sourceVoiceID": "zh-CN-liaoning-YunbiaoNeural",
          "voiceSuggestion": "凶神恶煞，占山为王，带东北口音的蛮横霸道",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000025",
          "title": "镖局总镖头",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "重信守诺，刀口舔血，声线沉稳饱经风霜",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000026",
          "title": "苗疆圣女",
          "sourceVoiceID": "zh-CN-XiaohanNeural",
          "voiceSuggestion": "神秘空灵，精通蛊术，声线缥缈如林间幽泉",
          "rateOffset": 0,
          "pitchOffset": 10,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000027",
          "title": "朝廷密探",
          "sourceVoiceID": "zh-CN-sichuan-YunxiNeural",
          "voiceSuggestion": "狡诈机敏，伪装高手，带四川方言的市井伪装",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000028",
          "title": "隐世高僧",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "看破红尘，不语凡尘，每句话都蕴含禅机",
          "rateOffset": -20,
          "pitchOffset": -10,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000029",
          "title": "世外仙姑",
          "sourceVoiceID": "zh-CN-XiaorouNeural",
          "voiceSuggestion": "温柔出尘，不食人间烟火，声音如春风拂面",
          "rateOffset": -5,
          "pitchOffset": 5,
          "style": "gentle"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000002a",
          "title": "少林武僧",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "赤诚刚猛，金刚怒目，声如铜钟正气浩然",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000002b",
          "title": "武当大师姐",
          "sourceVoiceID": "zh-CN-XiaoyanNeural",
          "voiceSuggestion": "清冷严厉，代师授艺，语气中透着对自己的高要求",
          "rateOffset": 0,
          "pitchOffset": -5,
          "style": "serious"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000002c",
          "title": "唐门门主",
          "sourceVoiceID": "zh-CN-YunjieNeural",
          "voiceSuggestion": "深沉内敛，用毒世家，语调平静却令人畏惧",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "calm"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000002d",
          "title": "天山童姥",
          "sourceVoiceID": "zh-CN-XiaomengNeural",
          "voiceSuggestion": "童颜老怪，喜怒无常，声音稚嫩却老气横秋",
          "rateOffset": 10,
          "pitchOffset": 18,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000002e",
          "title": "塞外刀客",
          "sourceVoiceID": "zh-CN-shaanxi-XiaoniNeural",
          "voiceSuggestion": "风沙磨砺，独行天涯，带陕西口音的沧桑与孤傲",
          "rateOffset": 0,
          "pitchOffset": 0,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-00000000002f",
          "title": "江南才子",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "风流倜傥，吟诗作赋，声线温润如玉儒雅随和",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "lyrical"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000030",
          "title": "蒙古勇士",
          "sourceVoiceID": "zh-CN-YunhaoNeural",
          "voiceSuggestion": "粗犷豪迈，骑射无双，声如洪钟带着草原的野性",
          "rateOffset": 5,
          "pitchOffset": 10,
          "style": "angry"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000031",
          "title": "女飞贼",
          "sourceVoiceID": "zh-CN-XiaoyuNeural",
          "voiceSuggestion": "狡黠灵动，来去如风，声音俏皮带着得意",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000032",
          "title": "丐帮长老",
          "sourceVoiceID": "zh-CN-YunjianNeural",
          "voiceSuggestion": "德高望重，手持打狗棒，言语间透着江湖智慧",
          "rateOffset": -5,
          "pitchOffset": 0,
          "style": "neutral"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000033",
          "title": "魔教圣女",
          "sourceVoiceID": "zh-CN-XiaochenNeural",
          "voiceSuggestion": "凄美决绝，为爱叛教，声音哀婉中带着决然",
          "rateOffset": 0,
          "pitchOffset": 5,
          "style": "depressed"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000034",
          "title": "小和尚",
          "sourceVoiceID": "zh-CN-XiaoruiNeural",
          "voiceSuggestion": "天真无邪，懵懂问道，声音清脆充满好奇",
          "rateOffset": 10,
          "pitchOffset": 15,
          "style": "cheerful"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000035",
          "title": "崆峒掌门",
          "sourceVoiceID": "zh-CN-YunzeNeural",
          "voiceSuggestion": "古板守旧，门派之见极深，语气中充满固执",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "disgruntled"
        },
        {
          "id": "a1b2c3d4-0008-4000-8000-000000000036",
          "title": "峨眉师太",
          "sourceVoiceID": "zh-CN-XiaozhenNeural",
          "voiceSuggestion": "清规戒律，不近人情，语调严厉如寒冰",
          "rateOffset": -5,
          "pitchOffset": -5,
          "style": "serious"
        }
      ]
    }
  ]
}
"""#
        guard let data = raw.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let export = try? decoder.decode(TemplateExport.self, from: data) else { return nil }
        return export.templates
    }
}
