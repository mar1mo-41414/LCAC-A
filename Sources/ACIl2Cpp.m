#import "ACIl2Cpp.h"
#import "ACDebugLog.h"
#import <dlfcn.h>
#import <string.h>

// ---------------------------------------------------------------------------
// il2cpp API (UnityFramework の export)
// ---------------------------------------------------------------------------

typedef void Il2CppDomain;
typedef void Il2CppAssembly;
typedef void Il2CppImage;
typedef void Il2CppClass;
typedef void FieldInfo;
typedef struct MethodInfo {
    void *methodPointer; // 先頭が実装アドレス (il2cpp の MethodInfo レイアウト)
} MethodInfo;

typedef struct Il2CppArray {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    void *vector[0];
} Il2CppArray;

static Il2CppDomain *(*p_domain_get)(void);
static const Il2CppAssembly **(*p_domain_get_assemblies)(const Il2CppDomain *, size_t *);
static const Il2CppImage *(*p_assembly_get_image)(const Il2CppAssembly *);
static const char *(*p_image_get_name)(const Il2CppImage *);
static Il2CppClass *(*p_class_from_name)(const Il2CppImage *, const char *, const char *);
static const MethodInfo *(*p_class_get_method_from_name)(Il2CppClass *, const char *, int);
static Il2CppClass *(*p_class_get_parent)(Il2CppClass *);
static FieldInfo *(*p_class_get_field_from_name)(Il2CppClass *, const char *);
static void (*p_field_static_get_value)(FieldInfo *, void *);
static void (*p_runtime_class_init)(Il2CppClass *);
static const Il2CppImage *(*p_get_corlib)(void);

// ---------------------------------------------------------------------------
// ゲーム側のメソッド (Cpp2IL ダンプで確認したシグネチャ)
//   すべて instance メソッドで、最終引数に MethodInfo* を取る il2cpp の呼び出し規約。
// ---------------------------------------------------------------------------

typedef BOOL (*BoolGetter)(void *self, const MethodInfo *mi);
typedef void *(*ObjGetter)(void *self, const MethodInfo *mi);
typedef void (*FloatSetter)(void *self, float value, const MethodInfo *mi);

static FieldInfo *gContextsSharedField;   // Contexts._sharedInstance (static)
static Il2CppClass *gContextsClass;

static const MethodInfo *m_Contexts_get_game;
static const MethodInfo *m_Ctx_GetEntities;          // Entitas.Context<GameEntity>.GetEntities()
static const MethodInfo *m_Game_isLevelPlaying;
static const MethodInfo *m_Game_isLevelComplete;
static const MethodInfo *m_Game_isLevelFailed;
static const MethodInfo *m_Game_isCleanupLevel;
static const MethodInfo *m_Game_hasArrowGrid;
static const MethodInfo *m_Ent_hasArrowId;
static const MethodInfo *m_Ent_isMoving;
static const MethodInfo *m_Ent_isDestroyed;
static const MethodInfo *m_Ent_hasBlocked;
static const MethodInfo *m_Ent_isTryToMove;
static const MethodInfo *m_Ent_hasAutoRemoveTimer;
static const MethodInfo *m_Ent_ReplaceAutoRemoveTimer;

static const MethodInfo *m_Contexts_get_ui;
static const MethodInfo *m_Contexts_get_service;
static const MethodInfo *m_Game_hasStartLevel;
static const MethodInfo *m_Game_hasTryStartLevel;
static const MethodInfo *m_Ui_isActiveMainMenuScreen;
static const MethodInfo *m_Svc_get_popupService;     // -> PopupServiceComponent (.Value @0x10)
static const MethodInfo *m_Svc_get_mainMenuService;  // -> MainMenuServiceComponent (.Value @0x10)
static Il2CppClass *gPopupServiceClass;
static Il2CppClass *gMainMenuServiceClass;
static const MethodInfo *m_Popup_HasAnyPopupOrDialogOpen;
static const MethodInfo *m_MainMenu_StartGame;

static BOOL gResolved = NO;

#define LOAD_API(var, name) do { \
    var = dlsym(RTLD_DEFAULT, name); \
    if (!var) { ACLog(@"dlsym failed: %s", name); return NO; } \
} while (0)

static BOOL ACLoadApi(void) {
    static BOOL loaded = NO;
    if (loaded) return YES;
    LOAD_API(p_domain_get, "il2cpp_domain_get");
    LOAD_API(p_domain_get_assemblies, "il2cpp_domain_get_assemblies");
    LOAD_API(p_assembly_get_image, "il2cpp_assembly_get_image");
    LOAD_API(p_image_get_name, "il2cpp_image_get_name");
    LOAD_API(p_class_from_name, "il2cpp_class_from_name");
    LOAD_API(p_class_get_method_from_name, "il2cpp_class_get_method_from_name");
    LOAD_API(p_class_get_parent, "il2cpp_class_get_parent");
    LOAD_API(p_class_get_field_from_name, "il2cpp_class_get_field_from_name");
    LOAD_API(p_field_static_get_value, "il2cpp_field_static_get_value");
    LOAD_API(p_runtime_class_init, "il2cpp_runtime_class_init");
    LOAD_API(p_get_corlib, "il2cpp_get_corlib");
    loaded = YES;
    return YES;
}

static const Il2CppImage *ACFindImage(const char *name) {
    Il2CppDomain *domain = p_domain_get();
    if (!domain) return NULL;
    size_t count = 0;
    const Il2CppAssembly **assemblies = p_domain_get_assemblies(domain, &count);
    if (!assemblies) return NULL;
    for (size_t i = 0; i < count; i++) {
        const Il2CppImage *image = p_assembly_get_image(assemblies[i]);
        const char *imageName = image ? p_image_get_name(image) : NULL;
        if (imageName && strcmp(imageName, name) == 0) return image;
    }
    return NULL;
}

/// klass から親方向にたどってメソッドを探す (Entitas.Context<T> の継承メソッド用)。
static const MethodInfo *ACFindMethod(Il2CppClass *klass, const char *name, int argc) {
    for (Il2CppClass *k = klass; k; k = p_class_get_parent(k)) {
        const MethodInfo *mi = p_class_get_method_from_name(k, name, argc);
        if (mi) return mi;
    }
    ACLog(@"method not found: %s/%d", name, argc);
    return NULL;
}

BOOL ACIl2CppResolve(void) {
    if (gResolved) return YES;
    if (!ACLoadApi()) return NO;

    // il2cpp_init 完了前に domain_get 等を呼ぶと未初期化の GC からアロケートしかねないので、
    // 副作用の無い il2cpp_get_corlib (初期化済みなら非 NULL) で準備完了を判定する。
    if (!p_get_corlib()) return NO;

    // アセンブリ一覧にまだ無ければ単に後で再試行。
    const Il2CppImage *image = ACFindImage("Assembly-CSharp.dll");
    if (!image) return NO;

    Il2CppClass *contexts = p_class_from_name(image, "", "Contexts");
    Il2CppClass *gameContext = p_class_from_name(image, "", "GameContext");
    Il2CppClass *gameEntity = p_class_from_name(image, "", "GameEntity");
    Il2CppClass *uiContext = p_class_from_name(image, "", "UiContext");
    Il2CppClass *serviceContext = p_class_from_name(image, "", "ServiceContext");
    gPopupServiceClass = p_class_from_name(image, "", "PopupService");
    gMainMenuServiceClass = p_class_from_name(image, "", "MainMenuService");
    if (!contexts || !gameContext || !gameEntity || !uiContext || !serviceContext
        || !gPopupServiceClass || !gMainMenuServiceClass) {
        ACLog(@"class not found: Contexts=%p GameContext=%p GameEntity=%p UiContext=%p ServiceContext=%p PopupService=%p MainMenuService=%p",
              contexts, gameContext, gameEntity, uiContext, serviceContext, gPopupServiceClass, gMainMenuServiceClass);
        return NO;
    }

    gContextsClass = contexts;
    gContextsSharedField = p_class_get_field_from_name(contexts, "_sharedInstance");
    m_Contexts_get_game = ACFindMethod(contexts, "get_game", 0);

    m_Ctx_GetEntities = ACFindMethod(gameContext, "GetEntities", 0);
    m_Game_isLevelPlaying = ACFindMethod(gameContext, "get_isLevelPlaying", 0);
    m_Game_isLevelComplete = ACFindMethod(gameContext, "get_isLevelComplete", 0);
    m_Game_isLevelFailed = ACFindMethod(gameContext, "get_isLevelFailed", 0);
    m_Game_isCleanupLevel = ACFindMethod(gameContext, "get_isCleanupLevel", 0);
    m_Game_hasArrowGrid = ACFindMethod(gameContext, "get_hasArrowGrid", 0);

    m_Ent_hasArrowId = ACFindMethod(gameEntity, "get_hasArrowId", 0);
    m_Ent_isMoving = ACFindMethod(gameEntity, "get_isMoving", 0);
    m_Ent_isDestroyed = ACFindMethod(gameEntity, "get_isDestroyed", 0);
    m_Ent_hasBlocked = ACFindMethod(gameEntity, "get_hasBlocked", 0);
    m_Ent_isTryToMove = ACFindMethod(gameEntity, "get_isTryToMove", 0);
    m_Ent_hasAutoRemoveTimer = ACFindMethod(gameEntity, "get_hasAutoRemoveTimer", 0);
    m_Ent_ReplaceAutoRemoveTimer = ACFindMethod(gameEntity, "ReplaceAutoRemoveTimer", 1);

    m_Contexts_get_ui = ACFindMethod(contexts, "get_ui", 0);
    m_Contexts_get_service = ACFindMethod(contexts, "get_service", 0);
    m_Game_hasStartLevel = ACFindMethod(gameContext, "get_hasStartLevel", 0);
    m_Game_hasTryStartLevel = ACFindMethod(gameContext, "get_hasTryStartLevel", 0);
    m_Ui_isActiveMainMenuScreen = ACFindMethod(uiContext, "get_isActiveMainMenuScreen", 0);
    m_Svc_get_popupService = ACFindMethod(serviceContext, "get_popupService", 0);
    m_Svc_get_mainMenuService = ACFindMethod(serviceContext, "get_mainMenuService", 0);
    m_Popup_HasAnyPopupOrDialogOpen = ACFindMethod(gPopupServiceClass, "HasAnyPopupOrDialogOpen", 0);
    m_MainMenu_StartGame = ACFindMethod(gMainMenuServiceClass, "StartGame", 0);

    const MethodInfo *all[] = {
        m_Contexts_get_game, m_Ctx_GetEntities,
        m_Game_isLevelPlaying, m_Game_isLevelComplete, m_Game_isLevelFailed,
        m_Game_isCleanupLevel, m_Game_hasArrowGrid,
        m_Ent_hasArrowId, m_Ent_isMoving, m_Ent_isDestroyed, m_Ent_hasBlocked,
        m_Ent_isTryToMove, m_Ent_hasAutoRemoveTimer, m_Ent_ReplaceAutoRemoveTimer,
        m_Contexts_get_ui, m_Contexts_get_service, m_Game_hasStartLevel, m_Game_hasTryStartLevel,
        m_Ui_isActiveMainMenuScreen, m_Svc_get_popupService, m_Svc_get_mainMenuService,
        m_Popup_HasAnyPopupOrDialogOpen, m_MainMenu_StartGame,
    };
    for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); i++) {
        if (!all[i] || !all[i]->methodPointer) {
            ACLog(@"resolve failed at method index %zu", i);
            return NO;
        }
    }
    if (!gContextsSharedField) {
        ACLog(@"field Contexts._sharedInstance not found");
        return NO;
    }

    gResolved = YES;
    ACLog(@"il2cpp resolved OK");
    return YES;
}

static inline BOOL CallBool(const MethodInfo *mi, void *self) {
    return ((BoolGetter)mi->methodPointer)(self, mi);
}

static inline void *CallObj(const MethodInfo *mi, void *self) {
    return ((ObjGetter)mi->methodPointer)(self, mi);
}

static void *ACGetContexts(void) {
    static BOOL classInited = NO;
    if (!classInited) {
        // static フィールド領域の確保を保証する。Contexts には明示的な static 初期化子が無いので
        // ゲーム側より先に走っても副作用は無い。
        p_runtime_class_init(gContextsClass);
        classInited = YES;
    }
    void *contexts = NULL;
    p_field_static_get_value(gContextsSharedField, &contexts);
    return contexts; // NULL = ゲームがまだ Contexts を作っていない
}

static void *ACGetGameContext(void) {
    void *contexts = ACGetContexts();
    return contexts ? CallObj(m_Contexts_get_game, contexts) : NULL;
}

/// ServiceContext の XxxServiceComponent から .Value を取り出し、期待したクラスか確認する。
static void *ACGetService(void *contexts, const MethodInfo *getter, Il2CppClass *expected) {
    void *service = CallObj(m_Contexts_get_service, contexts);
    if (!service) return NULL;
    void *component = CallObj(getter, service);
    if (!component) return NULL;
    void *value = *(void **)((uint8_t *)component + 0x10);
    if (!value) return NULL;
    // il2cpp オブジェクトの先頭ワードは Il2CppClass*。インターフェース経由の実体が
    // 想定したクラスでなければ呼ばない (アップデートで実装が差し替わった時の保険)。
    if (*(Il2CppClass **)value != expected) return NULL;
    return value;
}

static BOOL ACEnsureResolved(void) {
    if (gResolved) return YES;
    // 解決の試行は 1 秒に 1 回まで。
    static CFTimeInterval lastTry = 0;
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - lastTry < 1.0) return NO;
    lastTry = now;
    return ACIl2CppResolve();
}

ACGameState ACIl2CppQueryState(void) {
    ACGameState st = {0};
    if (!ACEnsureResolved()) return st;
    void *contexts = ACGetContexts();
    if (!contexts) return st;
    void *game = CallObj(m_Contexts_get_game, contexts);
    void *ui = CallObj(m_Contexts_get_ui, contexts);
    if (!game || !ui) return st;

    st.ready = YES;
    st.levelPlaying = CallBool(m_Game_isLevelPlaying, game);
    st.levelComplete = CallBool(m_Game_isLevelComplete, game);
    st.levelFailed = CallBool(m_Game_isLevelFailed, game);
    st.startPending = CallBool(m_Game_hasStartLevel, game) || CallBool(m_Game_hasTryStartLevel, game);
    st.mainMenuActive = CallBool(m_Ui_isActiveMainMenuScreen, ui);
    void *popup = ACGetService(contexts, m_Svc_get_popupService, gPopupServiceClass);
    st.popupOpen = popup ? CallBool(m_Popup_HasAnyPopupOrDialogOpen, popup) : YES; // 不明なら開いている扱い
    return st;
}

BOOL ACIl2CppStartGame(void) {
    if (!gResolved) return NO;
    void *contexts = ACGetContexts();
    if (!contexts) return NO;
    void *mainMenu = ACGetService(contexts, m_Svc_get_mainMenuService, gMainMenuServiceClass);
    if (!mainMenu) {
        ACLog(@"StartGame: MainMenuService not available");
        return NO;
    }
    ((void (*)(void *, const MethodInfo *))m_MainMenu_StartGame->methodPointer)(mainMenu, m_MainMenu_StartGame);
    ACLog(@"StartGame called");
    return YES;
}

BOOL ACIl2CppStep(void) {
    if (!ACEnsureResolved()) return NO;

    void *game = ACGetGameContext();
    if (!game) return NO;

    // レベルプレイ中以外 (メニュー・クリア演出・失敗画面) は何もしない。
    if (!CallBool(m_Game_hasArrowGrid, game)) return NO;
    if (!CallBool(m_Game_isLevelPlaying, game)) return NO;
    if (CallBool(m_Game_isLevelComplete, game)) return NO;
    if (CallBool(m_Game_isLevelFailed, game)) return NO;
    if (CallBool(m_Game_isCleanupLevel, game)) return NO;

    Il2CppArray *entities = (Il2CppArray *)CallObj(m_Ctx_GetEntities, game);
    if (!entities) return NO;

    void *candidate = NULL;
    for (uintptr_t i = 0; i < entities->max_length; i++) {
        void *e = entities->vector[i];
        if (!e) continue;
        if (!CallBool(m_Ent_hasArrowId, e)) continue;
        if (CallBool(m_Ent_isMoving, e)) continue;
        if (CallBool(m_Ent_isDestroyed, e)) continue;
        // hasBlocked はゲーム自身 (ArrowBlockSystem / ArrowGrid.Collides) が毎回再計算している
        // 「進行方向に他の矢印がいるか」フラグ。付いている矢印は絶対に触らない = ミスしない。
        if (CallBool(m_Ent_hasBlocked, e)) continue;
        if (CallBool(m_Ent_isTryToMove, e)) continue;
        if (CallBool(m_Ent_hasAutoRemoveTimer, e)) {
            // 既に積んだ矢印がまだ処理待ち (ポップアップ表示中など) → 追加で積まない。
            return NO;
        }
        if (!candidate) candidate = e;
    }
    if (!candidate) return NO;

    // タイマー 0 で自動除去キューへ。実際の除去はゲーム側 ArrowAutoRemoveSystem が
    // 「未ブロック」「ポップアップ無し」等を再確認したうえで isTryToMove を立てて行う。
    ((FloatSetter)m_Ent_ReplaceAutoRemoveTimer->methodPointer)(candidate, 0.0f, m_Ent_ReplaceAutoRemoveTimer);
    return YES;
}
