import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import {BreakpointType} from '../util/BreakpointType'
// ===================== 类型定义 =====================
interface LevelConfig {
  time: number;
  speed: number;
  maxScore: number;
}

interface Hammer {
  id: number;
  name: string;
  scoreMultiplier: number;
}

interface Target {
  x: number;
  y: number;
}

type GameRuleType = "mole" | "findColor" | "shoot" | "flip";
type FlipBoardSize = "4x4" | "6x6" | "8x8";

// ===================== 莫兰迪全局配色 =====================
const MORANDI_BG: ResourceColor = '#E6EDF3';
const MORANDI_CARD: ResourceColor = '#F1F6FA';
const MORANDI_BLUE: ResourceColor = '#7A98B2';
const MORANDI_RED: ResourceColor = '#C88A8A';
const MORANDI_GREEN_SUC: ResourceColor = '#98A98F';
const MORANDI_TEXT_HEAD: ResourceColor = '#3A434C';
const MORANDI_TEXT_DESC: ResourceColor = '#707B96';
const MORANDI_GAME_BG: ResourceColor = '#DDE6EE';

const BTN_UNSELECT_BG: ResourceColor = '#B0BCCC';
const BTN_UNSELECT_TEXT: ResourceColor = '#2A3440';
const BTN_SELECT_BG: ResourceColor = '#7A98B2';
const BTN_SELECT_TEXT: ResourceColor = '#FFFFFF';

// 本地存储标识
const PREFS_NAME = 'game_score_data';

@Entry
@Component
struct GameHub {
  @StorageProp('currentBreakpoint') curBp: string = 'sm';

  // 窗口宽度：多端适配核心依据
  @StorageLink('windowWidth') winWidth: number = 0;
  @State currentPage: string = "hub";
  @State username: string = "";
  @State currentRuleType: GameRuleType = "mole";

  // ========== 设备类型区分（多端部署核心） ==========
  @State isPhone: boolean = true;
  @State isTablet: boolean = false;
  @State isPadPro11: boolean = false;
  @State isIPad: boolean = false;

  // 游戏最高分
  @State moleHighScore: number = 0;
  @State findColorHighScore: number = 0;
  @State shootHighScore: number = 0;
  @State flipBestRecord4: number = 9999;
  @State flipBestRecord6: number = 9999;
  @State flipBestRecord8: number = 9999;

  // 定时器
  moleTimerID: number = 0;
  moleCountTimerID: number = 0;
  moleRefreshTimerID: number = 0;
  shootTimerID: number = 0;

  // 打地鼠
  @State selectedHammer: Hammer = { id: 1, name: "基础锤", scoreMultiplier: 1.0 };
  @State moleScore: number = 0;
  @State moleLevel: number = 1;
  @State moleTimeLeft: number = 30;
  @State molePassScore: number = 0;
  @State moleFailed: boolean = false;
  @State moleVisible: boolean[] = [false, false, false, false, false, false, false, false, false];
  @State moleCountdownNum: number = 3;
  @State molePaused: boolean = false;
  @State comboCount: number = 0;

  readonly levelConfig: LevelConfig[] = [
    { time: 30, speed: 1000, maxScore: 300 },
    { time: 30, speed: 700, maxScore: 350 },
    { time: 30, speed: 450, maxScore: 400 }
  ];

  hammerList: Hammer[] = [
    { id: 1, name: "基础锤", scoreMultiplier: 1.0 },
    { id: 2, name: "强化锤", scoreMultiplier: 1.5 },
    { id: 3, name: "精英锤", scoreMultiplier: 2.0 }
  ];

  // 颜色找茬
  @State findColorLevel: number = 1;
  @State gridSize: number = 4;
  @State colorList: string[] = [];
  @State diffIndex: number = 0;
  @State findColorWin: boolean = false;

  // 射击打靶
  @State targetList: Target[] = [];
  @State shootGameOver: boolean = false;

  // 记忆翻牌（8x8 网格全屏展示、无滚动）
  @State currentFlipSize: FlipBoardSize = "4x4";
  @State flipCards: number[] = [];
  @State removedIndexList: number[] = [];
  @State flipOpen: number[] = [];
  @State flipLock: boolean = false;
  @State totalFlipCount: number = 0;
  @State flipCol: number = 4;

  // 本地存储实例
  dataPreferences: preferences.Preferences | null = null;
  context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.judgeDeviceType();
    this.initLocalStorage();
    this.loadLocalScore();
    this.onWindowSizeChange();
  }

  aboutToDisappear(): void {
    this.clearAllTimer();
  }

  // ===================== 1. 设备判断 + 动态窗口监听（多端部署核心） =====================
  judgeDeviceType(): void {
    const w = this.winWidth;
    // 手机 < 700vp
    if (w < 700) {
      this.isPhone = true;
      this.isTablet = false;
      this.isPadPro11 = false;
      this.isIPad = false;
    }
    // 11英寸平板 700 ~ 1000vp
    else if (w >= 700 && w <= 1000) {
      this.isPhone = false;
      this.isTablet = true;
      this.isPadPro11 = true;
      this.isIPad = false;
    }
    // 大屏 iPad / 桌面平板 > 1000vp
    else {
      this.isPhone = false;
      this.isTablet = true;
      this.isPadPro11 = false;
      this.isIPad = true;
    }
  }

  // 窗口尺寸变化实时重适配（横竖屏、窗口缩放）
  onWindowSizeChange(): void {
    const win = AppStorage.Get<window.Window>('window');
    if (win) {
      win.on('windowSizeChange', () => {
        this.judgeDeviceType();
      });
    }
  }

  // 动态字体大小
  getFontSize(phoneSize: number, padSize: number): number {
    return this.isTablet ? padSize : phoneSize;
  }

  // 动态按钮高度
  getBtnHeight(phoneH: number, padH: number): number {
    return this.isTablet ? padH : phoneH;
  }

  // 内容最大宽度：保证 iPad / 平板 居中、不拉伸、8x8网格完整显示
  getContentWidth(): string {
    if (this.isIPad) return '620px';
    if (this.isPadPro11) return '560px';
    return '94%';
  }

  // ===================== 2. 本地数据存储（分数持久化） =====================
  async initLocalStorage(): Promise<void> {
    try {
      this.context = getContext(this) as common.UIAbilityContext;
      this.dataPreferences = await preferences.getPreferences(this.context, PREFS_NAME);
    } catch (err) {
      console.error("存储初始化失败：", JSON.stringify(err));
    }
  }

  async saveScoreToLocal(): Promise<void> {
    if (!this.dataPreferences) return;
    try {
      await this.dataPreferences.put('mole', this.moleHighScore);
      await this.dataPreferences.put('color', this.findColorHighScore);
      await this.dataPreferences.put('shoot', this.shootHighScore);
      await this.dataPreferences.put('flip4', this.flipBestRecord4);
      await this.dataPreferences.put('flip6', this.flipBestRecord6);
      await this.dataPreferences.put('flip8', this.flipBestRecord8);
      await this.dataPreferences.flush();
    } catch (err) {
      console.error("保存分数失败：", JSON.stringify(err));
    }
  }

  async loadLocalScore(): Promise<void> {
    if (!this.dataPreferences) return;
    try {
      this.moleHighScore = await this.dataPreferences.get('mole', 0) as number;
      this.findColorHighScore = await this.dataPreferences.get('color', 0) as number;
      this.shootHighScore = await this.dataPreferences.get('shoot', 0) as number;
      this.flipBestRecord4 = await this.dataPreferences.get('flip4', 9999) as number;
      this.flipBestRecord6 = await this.dataPreferences.get('flip6', 9999) as number;
      this.flipBestRecord8 = await this.dataPreferences.get('flip8', 9999) as number;
    } catch (err) {
      console.error("读取分数失败：", JSON.stringify(err));
    }
  }

  updateScore(): void {
    this.saveScoreToLocal();
  }

  // ===================== 通用工具 =====================
  clearAllTimer(): void {
    clearInterval(this.moleTimerID);
    clearInterval(this.moleCountTimerID);
    clearInterval(this.moleRefreshTimerID);
    clearInterval(this.shootTimerID);
  }

  calcMolePassScore(): void {
    const idx = Math.max(0, Math.min(this.moleLevel - 1, this.levelConfig.length - 1));
    const cfg = this.levelConfig[idx];
    this.molePassScore = Math.floor(cfg.maxScore * 0.8);
  }

  getRuleText(): string {
    switch (this.currentRuleType) {
      case "mole":
        return `【打地鼠】
1. 共3个关卡，速度逐级加快；
2. 连击加分，漏击清空连击；
3. 达到总分80%即可晋级。`;
      case "findColor":
        return `【颜色找茬】
1. 共10关，网格与色差逐步提升；
2. 点击唯一异色方块通关。`;
      case "shoot":
        return `【射击打靶】
1. 靶标从右向左移动；
2. 靶标移出屏幕则游戏结束。`;
      case "flip":
        return `【记忆翻牌】
1. 支持4×4/6×6/8×8三种棋盘；
2. 两两配对消除，记录最优步数。`;
      default:
        return "";
    }
  }

  // ===================== 游戏逻辑 =====================
  enterGameAfterRule(): void {
    switch (this.currentRuleType) {
      case "mole":
        this.clearAllTimer();
        this.moleScore = 0;
        this.moleLevel = 1;
        this.calcMolePassScore();
        this.comboCount = 0;
        this.currentPage = "hammerSelect";
        break;
      case "findColor":
        this.findColorLevel = 1;
        this.initFindColorGame();
        break;
      case "shoot":
        this.initShootGame();
        break;
      case "flip":
        this.currentPage = "flipSizeSelect";
        break;
    }
  }

  // 颜色找茬
  initFindColorGame(): void {
    this.findColorWin = false;
    if (this.findColorLevel <= 3) this.gridSize = 4;
    else if (this.findColorLevel <= 6) this.gridSize = 5;
    else this.gridSize = 6;

    const total = this.gridSize * this.gridSize;
    this.colorList = new Array(total).fill("");
    this.diffIndex = Math.floor(Math.random() * total);

    const baseR = Math.floor(Math.random() * 180) + 40;
    const baseG = Math.floor(Math.random() * 180) + 40;
    const baseB = Math.floor(Math.random() * 180) + 40;
    const diff = Math.max(2, 22 - this.findColorLevel * 2);

    for (let i = 0; i < total; i++) {
      this.colorList[i] = i === this.diffIndex
        ? `rgb(${baseR + diff},${baseG + diff},${baseB + diff})`
        : `rgb(${baseR},${baseG},${baseB})`;
    }
    this.currentPage = "findColorGame";
  }

  clickColorBlock(idx: number): void {
    if (this.findColorWin) return;
    if (idx === this.diffIndex) {
      this.findColorHighScore += 10;
      this.findColorWin = true;
      this.updateScore();
      if (this.findColorLevel < 10) {
        setTimeout(() => {
          this.findColorLevel++;
          this.initFindColorGame();
        }, 600);
      } else {
        setTimeout(() => this.currentPage = "findColorResult", 600);
      }
    }
  }

  // 打地鼠
  startMoleCountdown(): void {
    this.moleCountTimerID = setInterval(() => {
      if (this.moleCountdownNum > 1) {
        this.moleCountdownNum--;
      } else {
        clearInterval(this.moleCountTimerID);
        this.startMoleLevel();
        this.currentPage = "moleGame";
      }
    }, 1000);
  }

  startMoleLevel(): void {
    this.calcMolePassScore();
    const cfg = this.levelConfig[this.moleLevel - 1];
    this.moleTimeLeft = cfg.time;
    this.moleVisible = [false, false, false, false, false, false, false, false, false];
    this.molePaused = false;

    this.moleTimerID = setInterval(() => {
      if (!this.molePaused) {
        this.moleTimeLeft--;
        if (this.moleTimeLeft <= 0) {
          this.clearAllTimer();
          this.checkMolePass();
        }
      }
    }, 1000);

    this.moleRefreshTimerID = setInterval(() => {
      if (this.molePaused) return;
      this.comboCount = 0;
      this.moleVisible.fill(false);
      const idx = Math.floor(Math.random() * 9);
      this.moleVisible[idx] = true;
    }, cfg.speed);
  }

  hitMole(index: number): void {
    if (!this.moleVisible[index] || this.molePaused) return;
    const add = Math.floor(10 * this.selectedHammer.scoreMultiplier * (1 + this.comboCount * 0.1));
    this.moleScore += add;
    this.comboCount++;
    this.moleVisible[index] = false;
  }

  checkMolePass(): void {
    if (this.moleScore >= this.molePassScore) {
      if (this.moleLevel < 3) {
        this.moleLevel++;
        this.calcMolePassScore();
        this.comboCount = 0;
        this.moleCountdownNum = 3;
        this.currentPage = "moleCountdown";
        this.startMoleCountdown();
      } else {
        this.moleFailed = false;
        if (this.moleScore > this.moleHighScore) {
          this.moleHighScore = this.moleScore;
          this.updateScore();
        }
        this.currentPage = "moleResult";
      }
    } else {
      this.moleFailed = true;
      this.currentPage = "moleResult";
    }
  }

  // 射击打靶
  initShootGame(): void {
    this.clearAllTimer();
    this.shootHighScore = 0;
    this.shootGameOver = false;
    this.targetList = [];
    this.currentPage = "shootGame";

    this.shootTimerID = setInterval(() => {
      if (this.shootGameOver) return;
      if (Math.random() < 0.03) {
        this.targetList.push({ x: Math.floor(Math.random() * 70) + 15, y: Math.floor(Math.random() * 50) + 15 });
      }
      for (let i = 0; i < this.targetList.length; i++) {
        this.targetList[i].x -= 0.3;
        if (this.targetList[i].x < 0) {
          this.shootGameOver = true;
          this.updateScore();
          setTimeout(() => this.currentPage = "shootResult", 500);
          break;
        }
      }
    }, 30);
  }

  // 记忆翻牌（8x8 网格完整展示、无滚动）
  setFlipCol(): void {
    if (this.currentFlipSize === "6x6") this.flipCol = 6;
    else if (this.currentFlipSize === "8x8") this.flipCol = 8;
    else this.flipCol = 4;
  }

  initFlipGame(): void {
    this.flipCards = [];
    this.removedIndexList = [];
    this.flipOpen = [];
    this.flipLock = false;
    this.totalFlipCount = 0;
    this.setFlipCol();

    let size = 4;
    if (this.currentFlipSize === "6x6") size = 6;
    else if (this.currentFlipSize === "8x8") size = 8;

    const total = size * size;
    for (let i = 1; i <= total / 2; i++) {
      this.flipCards.push(i);
      this.flipCards.push(i);
    }
    // 洗牌
    let len = this.flipCards.length;
    for (let i = len - 1; i > 0; i--) {
      const r = Math.floor(Math.random() * (i + 1));
      // 修正写法（ArkTS 兼容）
      const temp = this.flipCards[i];
      this.flipCards[i] = this.flipCards[r];
      this.flipCards[r] = temp;
    }
    this.currentPage = "flipGame";
  }

  flipClick(idx: number): void {
    if (this.flipLock || this.flipOpen.includes(idx) || this.removedIndexList.includes(idx)) return;
    this.flipOpen.push(idx);
    this.totalFlipCount++;

    if (this.flipOpen.length === 2) {
      this.flipLock = true;
      const a = this.flipOpen[0];
      const b = this.flipOpen[1];
      if (this.flipCards[a] === this.flipCards[b]) {
        this.removedIndexList.push(a, b);
        this.flipOpen = [];
        this.flipLock = false;

        if (this.removedIndexList.length >= this.flipCards.length) {
          if (this.currentFlipSize === "4x4" && this.totalFlipCount < this.flipBestRecord4) {
            this.flipBestRecord4 = this.totalFlipCount;
          } else if (this.currentFlipSize === "6x6" && this.totalFlipCount < this.flipBestRecord6) {
            this.flipBestRecord6 = this.totalFlipCount;
          } else if (this.currentFlipSize === "8x8" && this.totalFlipCount < this.flipBestRecord8) {
            this.flipBestRecord8 = this.totalFlipCount;
          }
          this.updateScore();
          setTimeout(() => this.currentPage = "flipResult", 500);
        }
      } else {
        setTimeout(() => {
          this.flipOpen = [];
          this.flipLock = false;
        }, 800);
      }
    }
  }

  // ===================== 多端自适应UI构建 =====================
  build() {
    Column() {
      if (this.currentPage === "hub") this.hubPage()
      else if (this.currentPage === "login") this.loginPage()
      else if (this.currentPage === "gameRule") this.gameRulePage()
      else if (this.currentPage === "flipSizeSelect") this.flipSizeSelectPage()
      else if (this.currentPage === "hammerSelect") this.hammerSelectPage()
      else if (this.currentPage === "moleCountdown") this.moleCountdownPage()
      else if (this.currentPage === "moleGame") this.moleGamePage()
      else if (this.currentPage === "moleResult") this.moleResultPage()
      else if (this.currentPage === "findColorGame") this.findColorGamePage()
      else if (this.currentPage === "findColorResult") this.findColorResultPage()
      else if (this.currentPage === "shootGame") this.shootGamePage()
      else if (this.currentPage === "shootResult") this.shootResultPage()
      else if (this.currentPage === "flipGame") this.flipGamePage()
      else if (this.currentPage === "flipResult") this.flipResultPage()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(MORANDI_BG)
    .padding(this.isTablet ? { top: 20, bottom: 20, left: 16, right: 16 } : { top: 20, bottom: 20 })
  }

  @Builder
  BackBtn() {
    Button("← 返回大厅")
      .width('100%')
      .height(this.getBtnHeight(44, 40))
      .backgroundColor(BTN_UNSELECT_BG)
      .fontColor(BTN_UNSELECT_TEXT)
      .fontSize(this.getFontSize(16, 15))
      .onClick(() => this.currentPage = "hub")
  }

  @Builder
  gameRulePage() {
    Column() {
      Text("游戏规则")
        .fontSize(this.getFontSize(28, 26))
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 24 })
      Scroll() {
        Text(this.getRuleText())
          .fontSize(this.getFontSize(16, 15))
          .fontColor(MORANDI_TEXT_DESC)
          .lineHeight(26)
          .padding(16)
      }
      .width(this.getContentWidth())
      .height(this.isTablet ? 260 : 300)
      .backgroundColor(MORANDI_CARD)
      .borderRadius(12)
      Row() {
        Button("退出返回大厅")
          .width('42%')
          .height(this.getBtnHeight(48, 44))
          .backgroundColor(BTN_UNSELECT_BG)
          .fontColor(BTN_UNSELECT_TEXT)
          .onClick(() => this.currentPage = "hub")
        Button("开始游玩")
          .width('42%')
          .height(this.getBtnHeight(48, 44))
          .backgroundColor(MORANDI_BLUE)
          .fontColor(Color.White)
          .onClick(() => this.enterGameAfterRule())
      }
      .width(this.getContentWidth())
      .margin({ top: 24 })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(this.isTablet ? 16 : 20)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  flipSizeSelectPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text("选择棋盘规格").fontSize(this.getFontSize(26, 26)).margin({ bottom: 30 })
      Button("4 × 4（简单）")
        .width(this.getContentWidth())
        .height(this.getBtnHeight(50, 46))
        .margin(10)
        .backgroundColor(MORANDI_BLUE)
        .fontColor(Color.White)
        .onClick(() => { this.currentFlipSize = "4x4"; this.initFlipGame(); })
      Button("6 × 6（中等）")
        .width(this.getContentWidth())
        .height(this.getBtnHeight(50, 46))
        .margin(10)
        .backgroundColor(MORANDI_BLUE)
        .fontColor(Color.White)
        .onClick(() => { this.currentFlipSize = "6x6"; this.initFlipGame(); })
      Button("8 × 8（困难）")
        .width(this.getContentWidth())
        .height(this.getBtnHeight(50, 46))
        .margin(10)
        .backgroundColor(MORANDI_BLUE)
        .fontColor(Color.White)
        .onClick(() => { this.currentFlipSize = "8x8"; this.initFlipGame(); })
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  hubPage() {
    Scroll() {
      Column() {
        Text("休闲游戏馆")
          .fontSize(this.getFontSize(32, 32))
          .fontWeight(FontWeight.Bold)
          .fontColor(MORANDI_TEXT_HEAD)
          .margin({ top: 10 })
        Text("登录后即可进入全部小游戏")
          .fontSize(this.getFontSize(14, 14))
          .fontColor(MORANDI_TEXT_DESC)
          .margin({ bottom: 20 })
        Grid() {
          GridItem() {
            Column() {
              Text("打地鼠").fontSize(this.getFontSize(16, 16))
              Text(`${this.moleHighScore}`).fontSize(this.getFontSize(24, 24)).fontColor(MORANDI_BLUE)
            }
            .width('100%').padding(this.isTablet ? 14 : 12).backgroundColor(MORANDI_CARD).borderRadius(12)
          }
          GridItem() {
            Column() {
              Text("颜色找茬").fontSize(this.getFontSize(16, 16))
              Text(`${this.findColorHighScore}`).fontSize(this.getFontSize(24, 24)).fontColor(MORANDI_BLUE)
            }
            .width('100%').padding(this.isTablet ? 14 : 12).backgroundColor(MORANDI_CARD).borderRadius(12)
          }
          GridItem() {
            Column() {
              Text("射击打靶").fontSize(this.getFontSize(16, 16))
              Text(`${this.shootHighScore}`).fontSize(this.getFontSize(24, 24)).fontColor(MORANDI_BLUE)
            }
            .width('100%').padding(this.isTablet ? 14 : 12).backgroundColor(MORANDI_CARD).borderRadius(12)
          }
          GridItem() {
            Column() {
              Text("记忆翻牌").fontSize(this.getFontSize(16, 16))
              Text(`${this.flipBestRecord4 === 9999 ? "--" : this.flipBestRecord4}`)
                .fontSize(this.getFontSize(24, 24)).fontColor(MORANDI_BLUE)
            }
            .width('100%').padding(this.isTablet ? 14 : 12).backgroundColor(MORANDI_CARD).borderRadius(12)
          }
        }
        .columnsTemplate('1fr 1fr')
        .width(this.getContentWidth())
        .margin({ bottom: 24 }).columnsGap(14).rowsGap(14)

        Button("打地鼠")
          .width(this.getContentWidth())
          .height(this.getBtnHeight(50, 48))
          .margin({ bottom: 12 })
          .onClick(() => {
            if (this.username.length <= 0) this.currentPage = "login";
            else { this.currentRuleType = "mole"; this.currentPage = "gameRule"; }
          })
        Button("颜色找茬")
          .width(this.getContentWidth())
          .height(this.getBtnHeight(50, 48))
          .margin({ bottom: 12 })
          .onClick(() => {
            if (this.username.length <= 0) this.currentPage = "login";
            else { this.currentRuleType = "findColor"; this.currentPage = "gameRule"; }
          })
        Button("射击打靶")
          .width(this.getContentWidth())
          .height(this.getBtnHeight(50, 48))
          .margin({ bottom: 12 })
          .onClick(() => {
            if (this.username.length <= 0) this.currentPage = "login";
            else { this.currentRuleType = "shoot"; this.currentPage = "gameRule"; }
          })
        Button("记忆翻牌")
          .width(this.getContentWidth())
          .height(this.getBtnHeight(50, 48))
          .margin({ bottom: 12 })
          .onClick(() => {
            if (this.username.length <= 0) this.currentPage = "login";
            else { this.currentRuleType = "flip"; this.currentPage = "gameRule"; }
          })
        Text(this.username ? `已登录：${this.username}` : "尚未登录，点击游戏按钮前往登录")
          .margin({ top: 30, bottom: 20 }).fontSize(this.getFontSize(14, 14))
      }
      .width('100%').alignItems(HorizontalAlign.Center)
    }.layoutWeight(1)
  }

  @Builder
  loginPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text("玩家登录").fontSize(this.getFontSize(28, 28)).margin({ bottom: 30 })
      TextInput({ text: this.username, placeholder: "输入任意昵称" })
        .width(this.getContentWidth())
        .height(this.getBtnHeight(48, 44))
        .onChange((val: string) => this.username = val)
      Button("确认登录")
        .width(this.getContentWidth())
        .height(this.getBtnHeight(48, 44))
        .margin({ top: 20, bottom: 12 })
        .onClick(() => { if (this.username.trim()) this.currentPage = "hub"; })
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  hammerSelectPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text("选择锤子").fontSize(this.getFontSize(26, 26)).margin({ bottom: 30 })
      ForEach(this.hammerList, (item: Hammer) => {
        Button(`${item.name} 倍率:${item.scoreMultiplier}`)
          .width(this.getContentWidth())
          .margin(8)
          .height(this.getBtnHeight(48, 44))
          .backgroundColor(this.selectedHammer.id === item.id ? BTN_SELECT_BG : BTN_UNSELECT_BG)
          .fontColor(this.selectedHammer.id === item.id ? BTN_SELECT_TEXT : BTN_UNSELECT_TEXT)
          .onClick(() => this.selectedHammer = item)
      })
      Button("开始游戏")
        .width(this.getContentWidth())
        .height(this.getBtnHeight(50, 48))
        .margin({ top: 20 })
        .backgroundColor(MORANDI_BLUE)
        .fontColor(Color.White)
        .onClick(() => {
          this.moleCountdownNum = 3;
          this.currentPage = "moleCountdown";
          this.startMoleCountdown();
        })
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  moleCountdownPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text(`${this.moleCountdownNum}`).fontSize(this.getFontSize(100, 100)).fontWeight(FontWeight.Bold)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  @Builder
  moleGamePage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 10 })
      Row() {
        Text(`第${this.moleLevel}关 | 得分:${this.moleScore} / 通关线:${this.molePassScore} 剩余时间:${this.moleTimeLeft}`)
          .fontSize(this.getFontSize(16, 16))
      }.margin({ bottom: 20 })
      Column() {
        Grid() {
          ForEach(this.moleVisible, (visible: boolean, idx: number) => {
            GridItem() {
              Button(visible ? "🐹" : "")
                .width('100%').aspectRatio(1)
                .fontSize(this.getFontSize(32, 28))
                .backgroundColor(MORANDI_BLUE).fontColor(Color.White).borderRadius(10)
                .onClick(() => this.hitMole(idx))
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr').columnsGap(6).rowsGap(6)
      }
      .layoutWeight(1)
      .width(new BreakpointType('200','300','500').getValue(this.curBp))
      // .width(this.getContentWidth())
      .padding({ left: 12, right: 12 }).alignSelf(ItemAlign.Center)

      Row() {
        Text(`当前连击：${this.comboCount}`)
          .fontSize(this.getFontSize(18, 16)).padding(10)
          .backgroundColor(MORANDI_CARD).borderRadius(8).flexGrow(1).textAlign(TextAlign.Center)
        Button(this.molePaused ? "继续" : "暂停")
          .flexGrow(1).margin({ left: 6, right: 6 }).height(this.getBtnHeight(44, 40))
          .backgroundColor(MORANDI_GREEN_SUC).fontColor(Color.White)
          .onClick(() => this.molePaused = !this.molePaused)
        Button("退出本局")
          .flexGrow(1).height(this.getBtnHeight(44, 40))
          .backgroundColor(MORANDI_RED).fontColor(Color.White)
          .onClick(() => { this.clearAllTimer(); this.currentPage = "hub"; })
      }
      .width(this.getContentWidth())
      .margin({ top: 20 }).alignSelf(ItemAlign.Center)
    }
  }

  @Builder
  moleResultPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text(this.moleFailed ? "闯关失败（未达80%分数）" : "全部三关通关！")
        .fontSize(this.getFontSize(30, 28))
      Text(`本局总分：${this.moleScore}`).margin({ top: 10 }).fontSize(this.getFontSize(18, 18))
      Button("保存并返回首页")
        .margin({ top: 30 })
        .width(this.isTablet ? '65%' : '80%')
        .height(this.getBtnHeight(50, 48))
        .backgroundColor(MORANDI_BLUE).fontColor(Color.White)
        .onClick(() => {
          if (this.moleScore > this.moleHighScore) {
            this.moleHighScore = this.moleScore;
            this.updateScore();
          }
          this.currentPage = "hub";
        })
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  findColorGamePage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 10 })
      Text(`第 ${this.findColorLevel} / 10 关`).fontSize(this.getFontSize(24, 24)).margin({ bottom: 15 })
      Column() {
        Grid() {
          ForEach(this.colorList, (color: string, idx: number) => {
            GridItem() {
              Rect()
                .width('100%').aspectRatio(1).fill(color).borderRadius(6)
                .onClick(() => this.clickColorBlock(idx))
            }
          })
        }
        .columnsTemplate(`repeat(${this.gridSize}, 1fr)`).width('100%').columnsGap(6).rowsGap(6)
        //   .columnsTemplate(new BreakpointType('1fr 1fr','1fr 1fr 1fr','1fr 1fr 1fr 1fr').getValue(this.curBp))

      }
      .layoutWeight(1)
      // .width(this.getContentWidth())
      .width(new BreakpointType('200','300','500').getValue(this.curBp))
      .padding({ left: 12, right: 12 }).alignSelf(ItemAlign.Center)
    }
    .width('100%').padding({ top: 10 })
  }

  @Builder
  findColorResultPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text("恭喜通关全部10关！").fontSize(this.getFontSize(30, 28)).margin({ bottom: 10 })
      Text(`最终得分：${this.findColorHighScore}`).fontSize(this.getFontSize(18, 18))
      Button("保存返回首页")
        .margin({ top: 20 })
        .width(this.isTablet ? '65%' : '80%')
        .height(this.getBtnHeight(50, 48))
        .backgroundColor(MORANDI_BLUE).fontColor(Color.White)
        .onClick(() => this.currentPage = "hub")
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  shootGamePage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 10 })
      Text(`得分：${this.shootHighScore}`).fontSize(this.getFontSize(24, 24)).margin({ bottom: 20 })
      Stack() {
        ForEach(this.targetList, (t: Target) => {
          Ellipse()
            .width(this.isTablet ? 36 : 40).height(this.isTablet ? 36 : 40)
            .backgroundColor(MORANDI_RED)
            .position({ left: `${t.x}%`, top: `${t.y}%` })
            .onClick(() => { this.shootHighScore += 15; this.targetList = this.targetList.filter(item => item !== t); })
        })
      }
      .width(this.getContentWidth())
      .height(this.isTablet ? 280 : 300)
      .backgroundColor(MORANDI_GAME_BG).borderRadius(12).alignSelf(ItemAlign.Center)
    }.width('100%')
  }

  @Builder
  shootResultPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text("游戏结束").fontSize(this.getFontSize(30, 28))
      Text(`最终得分：${this.shootHighScore}`).fontSize(this.getFontSize(18, 18))
      Button("保存返回首页")
        .width(this.isTablet ? '65%' : '80%')
        .height(this.getBtnHeight(50, 48))
        .backgroundColor(MORANDI_BLUE).fontColor(Color.White)
        .onClick(() => {
          this.updateScore();
          this.currentPage = "hub";
        })
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  flipGamePage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 10 })
      Text(`规格:${this.currentFlipSize} | 本局翻牌:${this.totalFlipCount}`)
        .fontSize(this.getFontSize(18, 18)).margin({ bottom: 16 })
      Column() {
        Grid() {
          ForEach(this.flipCards, (num: number, idx: number) => {
            GridItem() {
              Column() {
                if (!this.removedIndexList.includes(idx)) {
                  Text(this.flipOpen.includes(idx) ? num.toString() : "?")
                    .width('100%').aspectRatio(1).textAlign(TextAlign.Center)
                  // 动态字体：8x8网格自动缩小字体，保证完整显示
                    .fontSize(this.isTablet
                      ? (this.flipCol === 8 ? 9 : this.flipCol === 6 ? 11 : 13)
                      : (this.flipCol === 8 ? 11 : this.flipCol === 6 ? 13 : 15))
                    .backgroundColor(MORANDI_BLUE).fontColor(Color.White).borderRadius(6)
                    .onClick(() => this.flipClick(idx))
                }
              }.width('100%').aspectRatio(1)
            }
          })
        }
        .columnsTemplate(`repeat(${this.flipCol}, 1fr)`)
        .width('100%').columnsGap(4).rowsGap(4)
      }
      .layoutWeight(1)
      .width(new BreakpointType('200','300','500').getValue(this.curBp))
      // .width(this.getContentWidth())
      .padding({ left: 12, right: 12 }).alignSelf(ItemAlign.Center)
    }
    .width('100%').height('100%').padding({ bottom: 10 })
  }

  @Builder
  flipResultPage() {
    Column() {
      Column() { this.BackBtn() }.margin({ bottom: 20 })
      Text("全部卡牌配对完毕，通关！").fontSize(this.getFontSize(28, 28)).margin({ bottom: 12 })
      Text(`本局翻牌总次数：${this.totalFlipCount}`).fontSize(this.getFontSize(18, 18))
      Button("返回首页")
        .margin({ top: 30 })
        .width(this.isTablet ? '65%' : '80%')
        .height(this.getBtnHeight(50, 48))
        .backgroundColor(MORANDI_BLUE).fontColor(Color.White)
        .onClick(() => this.currentPage = "hub")
    }.alignItems(HorizontalAlign.Center)
  }
}