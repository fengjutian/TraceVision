# 鸿蒙应用开发规范（HarmonyOS App Development Constitution）

> 版本：1.0 | 适用范围：HarmonyOS 4.x / 5.x Stage 模型 ArkTS/ArkUI 应用

---

## 一、技术原则

### 1.1 架构设计原则

#### 1.1.1 分层架构（强制）

应用必须遵循三层架构，各层职责严格分离：

```
┌─────────────────────────────────────┐
│         展示层 (Presentation)        │  ArkUI 组件、页面、状态管理
├─────────────────────────────────────┤
│          业务层 (Business)           │  UseCase、ViewModel、Service
├─────────────────────────────────────┤
│          数据层 (Data)               │  Repository、DataSource、DAO
└─────────────────────────────────────┘
```

- **展示层**：仅负责 UI 渲染与用户交互，不包含业务逻辑
- **业务层**：封装核心业务逻辑，不依赖具体 UI 框架
- **数据层**：统一数据访问接口，屏蔽本地存储与网络的差异

#### 1.1.2 模块化原则

- 按业务领域划分 HAP/HSP 模块，禁止跨业务直接调用内部实现
- 公共能力抽取为独立 HSP（Harmony Shared Package），通过接口暴露
- 模块间通信使用 EventHub 或依赖注入，禁止硬编码模块路径

#### 1.1.3 单一职责原则

- 每个组件/类/函数只承担一项职责
- 若一个文件超过 300 行，必须拆分
- 自定义组件不超过 150 行（含注释）

#### 1.1.4 依赖倒置原则

- 高层模块依赖抽象接口，不依赖具体实现
- 使用 `interface` 定义数据层契约，Repository 实现该接口
- 禁止展示层直接 `import` 数据层具体实现类

### 1.2 技术选型原则

| 场景 | 推荐方案 | 禁止方案 |
|------|---------|---------|
| 状态管理 | `@State` / `@Observed` / AppStorage | 全局变量 |
| 跨组件通信 | `@Link` / `@Provide` / `@Consume` / EventHub | 直接引用父组件 |
| 本地存储 | Preferences / RelationalStore | 直接读写文件存储敏感数据 |
| 网络请求 | `@ohos/axios` 或 `http` 模块封装层 | 在组件 `build()` 中直接调用 |
| 异步处理 | `async/await` + `Promise` | 裸 callback 嵌套超过 2 层 |
| 路由导航 | Router / Navigation 组件 | 硬编码页面 URL 字符串 |

### 1.3 性能设计原则

- **懒加载**：列表使用 `LazyForEach`，大图使用按需加载
- **避免过渡绘制**：组件树深度不超过 10 层，减少透明度叠加
- **冷启动优化**：首屏资源不超过 200 KB，延迟加载非首屏逻辑
- **内存管控**：大对象（图片、音视频）使用完毕后主动释放引用
- **主线程保护**：耗时操作（IO、加密、大量计算）必须在 Worker 或 TaskPool 中执行

---

## 二、代码规范

### 2.1 命名规范

#### 2.1.1 通用规则

| 元素 | 命名规则 | 示例 |
|------|---------|------|
| 文件名 | `kebab-case` | `user-profile.ets`, `home-page.ets` |
| 自定义组件 | `PascalCase` | `UserProfileCard`, `HomeHeader` |
| 类、接口、枚举 | `PascalCase` | `UserRepository`, `INetworkService` |
| 函数、方法 | `camelCase`，动词开头 | `fetchUserData()`, `onLoginClick()` |
| 变量、属性 | `camelCase` | `userName`, `isLoading` |
| 常量 | `UPPER_SNAKE_CASE` | `MAX_RETRY_COUNT`, `BASE_URL` |
| 枚举值 | `UPPER_SNAKE_CASE` | `UserStatus.LOGGED_IN` |
| 私有成员 | 以 `_` 开头（可选，团队统一） | `_cache`, `_handler` |

#### 2.1.2 布尔命名

布尔类型变量/属性使用 `is`、`has`、`can`、`should` 前缀：

```typescript
// ✅ 正确
let isVisible: boolean = true;
let hasPermission: boolean = false;
let canRetry: boolean = true;

// ❌ 错误
let visible: boolean = true;
let permission: boolean = false;
```

#### 2.1.3 禁止的命名

- 禁止单字母变量（循环变量 `i`、`j`、`k` 除外）
- 禁止拼音命名（如 `yonghu`、`shouye`）
- 禁止无意义命名（如 `data1`、`temp2`、`xxx`）
- 禁止缩写歧义（如 `usrNm` → 应写 `userName`）

### 2.2 文件与目录结构

```
entry/src/main/
├── ets/
│   ├── pages/            # 页面（路由节点）
│   ├── components/       # 可复用组件
│   │   ├── common/       # 通用基础组件
│   │   └── business/     # 业务组件
│   ├── viewmodel/        # ViewModel（MVVM）
│   ├── service/          # 业务服务层
│   ├── repository/       # 数据仓库层
│   ├── datasource/       # 数据源（网络/本地）
│   ├── model/            # 数据模型（DTO/VO/Entity）
│   ├── utils/            # 工具函数
│   ├── constants/        # 常量定义
│   └── entryability/     # Ability 入口
├── resources/
│   ├── base/
│   │   ├── element/      # 字符串、颜色、尺寸资源
│   │   ├── media/        # 图片资源
│   │   └── layout/       # 布局资源（如有）
│   └── rawfile/          # 原始文件资源
└── module.json5
```

### 2.3 代码格式规范

#### 2.3.1 缩进与空白

- 使用 **2 个空格**缩进，禁止 Tab
- 运算符两侧保留空格：`a + b`，而非 `a+b`
- 逗号后保留空格：`func(a, b, c)`
- 花括号前保留空格：`if (cond) {`
- 每行最大 **120 个字符**

#### 2.3.2 分号与引号

- 语句末尾必须加分号 `;`
- 字符串使用单引号 `'`，模板字符串使用反引号 `` ` ``
- 对象 key 无需引号，除非含特殊字符

#### 2.3.3 类型声明

```typescript
// ✅ 必须显式声明类型
let count: number = 0;
const title: string = 'Hello';
function greet(name: string): string { ... }

// ❌ 禁止使用 any
let data: any = {};   // 违规

// ✅ 用 unknown 代替 any，并做类型收窄
let response: unknown = fetchData();
if (typeof response === 'string') { ... }
```

#### 2.3.4 注释规范

**文件头注释**（每个 `.ets` 文件必须包含）：

```typescript
/**
 * @file    用户个人资料页面
 * @desc    展示用户基本信息，支持头像、昵称编辑
 * @author  开发者姓名
 * @date    2026-03-24
 */
```

**函数/方法注释**（public 方法必须，private 方法建议）：

```typescript
/**
 * 获取用户信息
 * @param userId - 用户唯一标识
 * @returns 用户信息对象，失败时返回 null
 * @throws NetworkError 网络异常时抛出
 */
async getUserById(userId: string): Promise<UserInfo | null> { ... }
```

**行内注释**：
- 解释"为什么"，而非"是什么"
- 注释与代码同缩进，使用 `// ` 前缀（注意空格）

**禁止的注释**：
- 注释掉的无用代码（应直接删除，通过 Git 找回）
- `// TODO` 超过 7 天未处理必须转为 Issue
- `// HACK`、`// FIXME` 必须附带 Issue 链接

### 2.4 ArkUI 组件规范

#### 2.4.1 组件结构顺序

```typescript
@Component
struct UserCard {
  // 1. 装饰器属性（@State, @Prop, @Link 等）
  @State private isExpanded: boolean = false;
  @Prop userName: string = '';

  // 2. 生命周期方法（按调用顺序）
  aboutToAppear(): void { ... }
  aboutToDisappear(): void { ... }

  // 3. 私有方法
  private handleClick(): void { ... }

  // 4. build 方法（最后）
  build() {
    Column() { ... }
  }
}
```

#### 2.4.2 状态管理规范

- `@State` 仅用于组件内部状态，不跨组件直接传递
- 跨层级数据使用 `@Provide` / `@Consume`，命名必须语义化
- 全局状态使用 `AppStorage`，Key 定义在常量文件中
- 持久化状态使用 `PersistentStorage`，仅存储序列化简单数据

#### 2.4.3 禁止的 UI 写法

```typescript
// ❌ 禁止在 build() 中有副作用
build() {
  this.loadData(); // 违规：副作用
  Column() { ... }
}

// ❌ 禁止在 build() 中直接修改状态
build() {
  this.count++; // 违规
  Text(`${this.count}`)
}

// ✅ 正确：在生命周期或事件回调中处理
aboutToAppear(): void {
  this.loadData();
}
```

### 2.5 异步与错误处理规范

```typescript
// ✅ 统一使用 async/await，并处理异常
async function fetchUser(id: string): Promise<UserInfo> {
  try {
    const response = await httpClient.get<UserInfo>(`/users/${id}`);
    return response.data;
  } catch (error) {
    Logger.error('fetchUser', `Failed to fetch user ${id}`, error);
    throw new BusinessError(ErrorCode.NETWORK_ERROR, '获取用户信息失败');
  }
}

// ❌ 禁止忽略 Promise 错误
fetchUser(id); // 违规：未 await 且未处理错误
```

---

## 三、安全要求

### 3.1 权限管理

#### 3.1.1 权限最小化原则（强制）

- 只在 `module.json5` 中声明功能实际需要的权限
- 危险权限（如位置、摄像头、通讯录）必须在运行时动态申请
- 每次申请权限前必须向用户说明用途

```typescript
// ✅ 运行时权限申请示例
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';

async function requestLocationPermission(): Promise<boolean> {
  const atManager = abilityAccessCtrl.createAtManager();
  const result = await atManager.requestPermissionsFromUser(
    getContext(this),
    ['ohos.permission.LOCATION']
  );
  return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
}
```

#### 3.1.2 权限审批要求

| 权限级别 | 申请要求 |
|---------|---------|
| normal | `module.json5` 声明即可 |
| dangerous | 运行时申请 + 用户授权弹窗 + 拒绝后降级处理 |
| system_basic | 需系统签名，禁止普通应用申请 |

### 3.2 数据安全

#### 3.2.1 敏感数据存储（强制）

```typescript
// ✅ 使用 HUKS 存储密钥，使用加密存储敏感信息
import huks from '@ohos.security.huks';

// ❌ 禁止明文存储密码、Token、身份证号
const prefs = await preferences.getPreferences(context, 'user');
await prefs.put('password', '123456'); // 严重违规

// ❌ 禁止在日志中打印敏感信息
Logger.debug('login', `password: ${password}`); // 严重违规
```

敏感数据分类与处理要求：

| 数据类型 | 存储要求 | 传输要求 |
|---------|---------|---------|
| 密码、密钥 | HUKS 硬件加密 | 禁止传输原文 |
| Token / Cookie | 加密 Preferences | HTTPS only |
| 身份证、手机号 | AES-256 加密存储 | HTTPS + 脱敏展示 |
| 用户行为日志 | 本地脱敏 + 定期清理 | 加密传输，最小化字段 |

#### 3.2.2 数据传输安全

- **强制 HTTPS**：所有网络请求必须使用 HTTPS，禁止 HTTP 明文传输
- **证书校验**：生产环境必须开启服务端证书校验，禁止 `rejectUnauthorized: false`
- **防重放攻击**：敏感接口请求附加时间戳与 HMAC 签名
- **敏感参数**：禁止将 Token、密码等放在 URL Query 参数中

```typescript
// ❌ 禁止绕过证书校验
httpRequest.request(url, {
  usingProtocol: http.HttpProtocol.HTTP1_1,
  // rejectUnauthorized: false  // 严格禁止
});
```

### 3.3 输入验证与防注入

```typescript
// ✅ 所有用户输入必须验证
function validateUsername(input: string): boolean {
  const pattern = /^[a-zA-Z0-9_\u4e00-\u9fa5]{2,20}$/;
  return pattern.test(input);
}

// ✅ SQL 操作使用参数化查询，禁止字符串拼接
const sql = 'SELECT * FROM users WHERE id = ?';
rdbStore.querySql(sql, [userId]);

// ❌ 禁止字符串拼接 SQL
const sql = `SELECT * FROM users WHERE id = '${userId}'`; // SQL 注入风险
```

### 3.4 WebView 安全

```typescript
// ✅ WebView 安全配置
Web({ src: url, controller: this.controller })
  .javaScriptAccess(false)          // 生产环境禁用 JS（按需开启）
  .fileAccess(false)                // 禁止文件访问
  .domStorageAccess(false)          // 禁止 DOM Storage
  .onlineImageAccess(true)
```

- 禁止加载 `file://` 协议页面（可能导致本地文件泄漏）
- JS 注入接口必须严格校验调用方来源
- 白名单机制：仅允许加载可信域名的 URL

### 3.5 代码安全

- **禁止硬编码密钥/密码**：使用环境变量或 HUKS 管理
- **禁止输出调试信息到生产日志**：发布前必须关闭 Verbose/Debug 级别日志
- **混淆要求**：Release 包必须开启代码混淆（`buildProfileField`）
- **依赖安全**：第三方库必须使用官方源，定期扫描已知 CVE

---

## 四、质量标准

### 4.1 代码质量指标

| 指标 | 要求 | 工具 |
|------|------|------|
| 单函数行数 | ≤ 50 行 | ESLint / 人工审查 |
| 圈复杂度 | ≤ 10 | ESLint complexity |
| 文件行数 | ≤ 300 行 | 人工审查 |
| 重复代码率 | < 5% | SonarQube |
| 注释覆盖率（public API）| ≥ 80% | 人工审查 |
| TypeScript 严格模式 | 必须开启 `strict: true` | tsconfig |

### 4.2 测试要求

#### 4.2.1 测试覆盖率（CI 门禁）

| 层级 | 单元测试覆盖率 | 集成测试 |
|------|-------------|---------|
| 业务层（Service/UseCase）| ≥ 80% | 必须 |
| 数据层（Repository）| ≥ 70% | 必须 |
| 展示层（ViewModel）| ≥ 60% | 可选 |
| 工具函数（Utils）| ≥ 90% | — |

#### 4.2.2 测试规范

```typescript
// ✅ 测试用例命名规范：should_[期望行为]_when_[条件]
describe('UserService', () => {
  it('should_return_user_when_valid_id_provided', async () => {
    // Arrange
    const mockRepo = createMockUserRepository();
    const service = new UserService(mockRepo);
    // Act
    const user = await service.getUserById('user-001');
    // Assert
    expect(user).not.toBeNull();
    expect(user?.id).toBe('user-001');
  });

  it('should_throw_BusinessError_when_user_not_found', async () => {
    // ...
  });
});
```

- 每个测试用例只验证一个行为
- 使用 Mock 隔离外部依赖（网络、数据库）
- 禁止测试用例之间存在执行顺序依赖

### 4.3 性能质量基线

| 指标 | 目标值 | 告警阈值 |
|------|-------|---------|
| 冷启动时间 | < 1500ms | > 2000ms |
| 首帧渲染时间 | < 800ms | > 1200ms |
| 列表滑动帧率 | ≥ 60 fps | < 50 fps |
| 内存占用（前台）| < 200 MB | > 300 MB |
| 网络请求超时设置 | 10s | > 30s |
| 包体积（entry HAP）| < 50 MB | > 80 MB |

### 4.4 代码审查（CR）门禁

以下任意一项不通过，PR 不得合并：

- [ ] TypeScript 编译无错误（`strict: true`）
- [ ] 无 `any` 类型使用
- [ ] 单元测试全部通过
- [ ] 测试覆盖率达标（见 4.2.1）
- [ ] 无高危安全漏洞（SonarQube Security Hotspot 清零）
- [ ] 新增 public API 有 JSDoc 注释
- [ ] 无硬编码密钥/URL/敏感信息
- [ ] 性能敏感路径已通过 Profiler 验证

### 4.5 发布质量门禁

| 检查项 | 要求 |
|-------|------|
| 代码混淆 | Release 包必须开启 |
| 调试日志 | 生产包关闭 Verbose/Debug |
| 权限声明 | 仅保留实际使用的权限 |
| 第三方 SDK | 完成安全合规审核 |
| 崩溃率 | 上线后 ≤ 0.1%（7 日滚动）|
| ANR 率 | ≤ 0.05% |

### 4.6 日志规范

```typescript
// ✅ 使用统一 Logger 工具类，分级输出
import hilog from '@ohos.hilog';

class Logger {
  private static readonly DOMAIN = 0xF001;
  private static readonly TAG = 'TraceVision';

  static debug(tag: string, msg: string): void {
    if (BuildProfile.DEBUG) {
      hilog.debug(this.DOMAIN, this.TAG, `[${tag}] ${msg}`);
    }
  }

  static info(tag: string, msg: string): void {
    hilog.info(this.DOMAIN, this.TAG, `[${tag}] ${msg}`);
  }

  static error(tag: string, msg: string, error?: Error): void {
    hilog.error(this.DOMAIN, this.TAG, `[${tag}] ${msg}`, error?.message ?? '');
  }
}

// ❌ 禁止直接使用 console.log
console.log('user:', JSON.stringify(user)); // 违规：不分级、可能泄露敏感信息
```

日志规则：
- 禁止在日志中输出：密码、Token、身份证、手机号等敏感字段
- 生产环境仅保留 Info / Warn / Error 级别
- 日志消息使用英文（国际化友好），错误详情可中英文混合
- 每条日志必须包含模块标识 `[TagName]`

---

## 五、违规处理说明

| 违规级别 | 判定标准 | 处理方式 |
|---------|---------|---------|
| **严重（Blocker）** | 安全漏洞、硬编码密钥、明文存储密码、绕过证书校验 | PR 立即驳回，当日修复 |
| **高（Critical）** | 使用 `any`、无错误处理、无权限最小化、覆盖率不达标 | PR 驳回，下次迭代前修复 |
| **中（Major）** | 命名不规范、函数超长、缺少注释、使用禁止的写法 | 提 Comment，本次 PR 内修复 |
| **低（Minor）** | 格式问题、注释措辞、可选优化建议 | 提 Comment，作者自行决定 |
