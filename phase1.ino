// ==========================================================================
// PROJECT: ULTIMATE RGB INVADERS — FreeRTOS Multi-Task Architecture
// HARDWARE: ESP32-S3 (N16R8), WS2812B LEDs, SSD1306 OLED, 4 Buttons, Pot, Active Buzzer
// ==========================================================================
// RTOS ARCHITECTURE:
//   Task 1  vAnalogSensorTask   Core 0  Prio 2   50 ms   ADC pot → xPotQueue
//   Task 2  vDigitalInputTask   Core 1  Prio 3   ISR+10ms Buttons → g_buttons
//   Task 3  vGameProcessingTask Core 1  Prio 4   16 ms   State machine + leds[]
//   Task 4  vOutputTask         Core 1  Prio 5   event   FastLED.show()
//   Task 5  vOledCommTask       Core 0  Prio 2   120 ms  OLED HUD via I2C
//   Task 6  vLoggingTask        Core 0  Prio 1   500 ms  Serial diagnostics
//   Task 7  vBuzzerTask         Core 0  Prio 3   event   Active buzzer SFX
//   Task 8  vTelemetryTask      Core 0  Prio 1   100 ms  WebSocket JSON telemetry // AFTER UPDATE
//
// SYNCHRONISATION:
//   xPotQueue          Queue(5)       Analog task  → Game task
//   xBuzzerQueue       Queue(10)      Game task    → Buzzer task
//   xButtonISRSem      BinarySemaphore ISR          → Digital task
//   xRenderSem         BinarySemaphore Game task    → Output task
//   xInputMutex        Mutex          Digital task ↔ Game task
//   xSnapshotMutex     Mutex          Game task    ↔ OLED / Log tasks
//   xSerialMutex       Mutex          Log task     (Serial protection)
//   xTelemetryMutex    Mutex          Game task    ↔ Telemetry task LED mirror // AFTER UPDATE
//
//   ISR: onButtonISR() on FALLING edge of all 4 buttons
//   Timeout ops: xQueueSend, xSemaphoreTake with pdMS_TO_TICKS
// ==========================================================================

#define FASTLED_ESP32_S3_PIN 7
#define FASTLED_RMT_MAX_CHANNELS 1
#include <FastLED.h>
#include <vector>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <WiFi.h> // AFTER UPDATE
#include <WebSocketsServer.h> // AFTER UPDATE
#include <ArduinoJson.h> // AFTER UPDATE

// --------------------------------------------------------------------------
// 1. DEFINITIONS
// --------------------------------------------------------------------------
#define PIN_LED_DATA    7
#define MAX_LEDS        1200
#define LED_TYPE        WS2812B
#define COLOR_ORDER     GRB

#define PIN_BTN_BLUE    4
#define PIN_BTN_RED     5
#define PIN_BTN_GREEN   17
#define PIN_BTN_WHITE   18
#define POT_PIN         1
#define PIN_BUZZER      2   // Active buzzer signal pin

#define OLED_SDA        8
#define OLED_SCL        9
#define SCREEN_WIDTH    128
#define SCREEN_HEIGHT   64
#define OLED_RESET      -1
#define OLED_ADDRESS    0x3C

#define FRAME_DELAY     16
#define INPUT_BUFFER_MS 60
const int FIRE_COOLDOWN = 100;

// --------------------------------------------------------------------------
// HARDCODED CONFIG
// --------------------------------------------------------------------------
const int   CONFIG_NUM_LEDS       = 100;
const int   CONFIG_BRIGHTNESS_PCT = 50;
const int   CONFIG_START_LEVEL    = 1;
const bool  CONFIG_SACRIFICE_LED  = true;
const int   CONFIG_HOMEBASE_SIZE  = 3;
const int   CONFIG_SHOT_SPEED_PCT = 100;
const bool  CONFIG_ENDLESS_MODE   = false;
const int   ledStartOffset        = CONFIG_SACRIFICE_LED ? 1 : 0;

// --------------------------------------------------------------------------
// COLOR CONFIG
// --------------------------------------------------------------------------
CRGB col_c1, col_c2, col_c3, col_c4, col_c5, col_c6, col_cw, col_cb;

// --------------------------------------------------------------------------
// 2. DATA TYPES
// --------------------------------------------------------------------------
enum GameState {
    STATE_MENU, STATE_INTRO, STATE_PLAYING, STATE_BOSS_PLAYING,
    STATE_LEVEL_COMPLETED, STATE_GAME_FINISHED, STATE_BASE_DESTROYED, STATE_GAMEOVER,
    STATE_BONUS_INTRO, STATE_BONUS_PLAYING,
    STATE_BONUS_SIMON
};

enum Boss2State { B2_MOVE, B2_CHARGE, B2_SHOOT };
enum Boss3State { B3_MOVE, B3_PHASE_CHANGE, B3_BURST, B3_WAIT };
enum SimonState { S_MOVE, S_PREPARE, S_SHOW, S_INPUT, S_SUCCESS, S_FAIL };

struct LevelConfig  { int speed; int length; int bossType; };
struct BossConfig   { int moveSpeed; int shotSpeed; int hpPerLed; int shotFreq; int burstCount; int m1; int m2; int m3; };
struct Enemy        { int color; float pos; bool flash; };
struct BossSegment  { int color; int hp; int maxHp; bool active; int originalIndex; };
struct Shot         { float position; int color; };
struct BossProjectile { float pos; int color; };

// --- RTOS buzzer events ---
enum BuzzerEventType : uint8_t {
    BUZZER_EVENT_SHOT = 1,
    BUZZER_EVENT_LEVEL_CLEAR = 2
};

struct BuzzerEvent {
    BuzzerEventType type;
};

// --- RTOS shared button state ---
struct ButtonState {
    bool blue;
    bool red;
    bool green;
    bool white;
};

// --- RTOS snapshot for OLED / Log tasks ---
struct GameSnapshot {
    GameState state;
    int       level;
    int       score;
    int       enemiesRemaining;
    int       totalLevelEnemies;
    int       bossHpCurrent;
    int       bossHpMax;
    int       lvlAchievedScore;
    int       lvlMaxPossibleScore;
    int       bonusSpawned;
    int       bonusLivesVal;
    int       simonStageVal;
    int       simonLivesVal;
    int       currentBossTypeVal; // AFTER UPDATE
    int       activeProjectiles; // AFTER UPDATE
    int       comboColorVal; // AFTER UPDATE
    unsigned long stateTimerVal;
};

struct GameTelemetry { // AFTER UPDATE
    int level; // AFTER UPDATE
    long score; // AFTER UPDATE
    int enemiesRemaining; // AFTER UPDATE
    int bossHP; // AFTER UPDATE
    int maxBossHP; // AFTER UPDATE
    String gameState; // AFTER UPDATE
    int comboColor; // AFTER UPDATE
    int playerAccuracy; // AFTER UPDATE
    int activeProjectiles; // AFTER UPDATE
    int simonStage; // AFTER UPDATE
    bool beatSaberMode; // AFTER UPDATE
    bool simonMode; // AFTER UPDATE
}; // AFTER UPDATE

// --- Event streaming system (fixed-size, queue-friendly) --- // AFTER UPDATE
enum TelemetryEventType : uint8_t { // AFTER UPDATE
    EVT_STATE_CHANGE = 0, // AFTER UPDATE
    EVT_LEVEL_COMPLETED, // AFTER UPDATE
    EVT_BOSS_SPAWNED, // AFTER UPDATE
    EVT_BOSS_SEGMENT_DESTROYED, // AFTER UPDATE
    EVT_ENEMY_DESTROYED, // AFTER UPDATE
    EVT_COMBO_TRIGGERED, // AFTER UPDATE
    EVT_COMBO_FAILED, // AFTER UPDATE
    EVT_SIMON_STARTED, // AFTER UPDATE
    EVT_SIMON_COMPLETED, // AFTER UPDATE
    EVT_BEATSABER_STARTED, // AFTER UPDATE
    EVT_BEATSABER_COMPLETED, // AFTER UPDATE
    EVT_GAME_OVER, // AFTER UPDATE
    EVT_GAME_WON, // AFTER UPDATE
    EVT_BASE_DESTROYED // AFTER UPDATE
}; // AFTER UPDATE

struct TelemetryEvent { // AFTER UPDATE
    TelemetryEventType type; // AFTER UPDATE
    unsigned long timestamp; // AFTER UPDATE
    int level; // AFTER UPDATE
    int value1; // AFTER UPDATE
    int value2; // AFTER UPDATE
}; // AFTER UPDATE

// --- Bug reporting system --- // AFTER UPDATE
enum BugSeverity : uint8_t { // AFTER UPDATE
    BUG_LOW = 0, // AFTER UPDATE
    BUG_MEDIUM, // AFTER UPDATE
    BUG_HIGH, // AFTER UPDATE
    BUG_CRITICAL // AFTER UPDATE
}; // AFTER UPDATE

enum BugType : uint8_t { // AFTER UPDATE
    BUG_NEGATIVE_HP = 0, // AFTER UPDATE
    BUG_NEGATIVE_SCORE, // AFTER UPDATE
    BUG_INVALID_STATE, // AFTER UPDATE
    BUG_ACCURACY_OVERFLOW, // AFTER UPDATE
    BUG_ENEMY_COUNT_NEGATIVE, // AFTER UPDATE
    BUG_LEVEL_OVERFLOW, // AFTER UPDATE
    BUG_IMPOSSIBLE_COMBO, // AFTER UPDATE
    BUG_TELEMETRY_FAILURE, // AFTER UPDATE
    BUG_TASK_STALL // AFTER UPDATE
}; // AFTER UPDATE

struct BugReport { // AFTER UPDATE
    BugType type; // AFTER UPDATE
    BugSeverity severity; // AFTER UPDATE
    unsigned long timestamp; // AFTER UPDATE
    int level; // AFTER UPDATE
    int value1; // AFTER UPDATE
}; // AFTER UPDATE

// --- RTOS task heartbeat (lightweight, no dynamic alloc) --- // AFTER UPDATE
#define TASK_COUNT 8 // AFTER UPDATE
struct TaskHeartbeat { // AFTER UPDATE
    volatile unsigned long lastBeat; // AFTER UPDATE
    volatile unsigned long maxIntervalMs; // AFTER UPDATE
    const char* name; // AFTER UPDATE
}; // AFTER UPDATE

// --------------------------------------------------------------------------
// 3. RTOS HANDLES
// --------------------------------------------------------------------------
QueueHandle_t       xPotQueue        = NULL;   // int, depth 5
QueueHandle_t       xBuzzerQueue     = NULL;   // BuzzerEvent, depth 10
SemaphoreHandle_t   xButtonISRSem    = NULL;   // binary – ISR → digital task
SemaphoreHandle_t   xRenderSem       = NULL;   // binary – game → output task
SemaphoreHandle_t   xInputMutex      = NULL;   // mutex  – g_buttons protection
SemaphoreHandle_t   xSnapshotMutex   = NULL;   // mutex  – g_snapshot protection
SemaphoreHandle_t   xSerialMutex     = NULL;   // mutex  – Serial protection
SemaphoreHandle_t   xTelemetryMutex  = NULL;   // mutex  – telemetry LED mirror protection // AFTER UPDATE

TaskHandle_t hAnalogTask  = NULL;
TaskHandle_t hDigitalTask = NULL;
TaskHandle_t hGameTask    = NULL;
TaskHandle_t hOutputTask  = NULL;
TaskHandle_t hOledTask    = NULL;
TaskHandle_t hLogTask     = NULL;
TaskHandle_t hBuzzerTask  = NULL;
TaskHandle_t hTelemetryTask = NULL; // AFTER UPDATE

// --- Shared state (protected by mutexes) ---
ButtonState g_buttons = {false, false, false, false};
GameSnapshot         g_snapshot;

// --- FPS counter (written by game task, read by log task) ---
volatile unsigned long g_frameCount = 0;

const char* WIFI_SSID = "Led"; // AFTER UPDATE
const char* WIFI_PASSWORD = "123456789"; // AFTER UPDATE
WebSocketsServer webSocket = WebSocketsServer(81); // AFTER UPDATE
GameTelemetry telemetry; // AFTER UPDATE
unsigned long telemetryTimer = 0; // AFTER UPDATE
unsigned long telemetryWiFiRetryTimer = 0; // AFTER UPDATE
unsigned long telemetryWiFiConnectedAt = 0; // AFTER UPDATE
bool telemetryWebSocketStarted = false; // AFTER UPDATE
bool telemetryWiFiConnectedPrinted = false; // AFTER UPDATE
unsigned long telemetryPacketsSent = 0; // AFTER UPDATE
unsigned long telemetryLastDebugPrint = 0; // AFTER UPDATE
const unsigned long TELEMETRY_INTERVAL_MS = 100; // AFTER UPDATE
const unsigned long WIFI_RETRY_INTERVAL_MS = 10000; // AFTER UPDATE
const size_t TELEMETRY_JSON_RESERVE_BYTES = 8192; // AFTER UPDATE
String telemetryJsonPacket; // AFTER UPDATE
uint8_t telemetryLedMirror[MAX_LEDS] = {0}; // AFTER UPDATE
uint8_t telemetryLedPacket[MAX_LEDS] = {0}; // AFTER UPDATE
QueueHandle_t xEventQueue = NULL; // AFTER UPDATE
QueueHandle_t xBugQueue = NULL; // AFTER UPDATE
unsigned long telemetryLedTimer = 0; // AFTER UPDATE
unsigned long telemetryDiagTimer = 0; // AFTER UPDATE
const unsigned long TELEMETRY_LED_INTERVAL_MS = 150; // AFTER UPDATE
const unsigned long TELEMETRY_DIAG_INTERVAL_MS = 500; // AFTER UPDATE
TaskHeartbeat g_taskHeartbeats[TASK_COUNT]; // AFTER UPDATE
volatile unsigned long g_lastFrameTimeUs = 0; // AFTER UPDATE
volatile float g_currentFPS = 0.0; // AFTER UPDATE
GameState g_prevState = STATE_MENU; // AFTER UPDATE
int g_assertionFailures = 0; // AFTER UPDATE

// --------------------------------------------------------------------------
// 4. GLOBAL GAME VARIABLES (unchanged)
// --------------------------------------------------------------------------
CRGB leds[MAX_LEDS];

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
bool oledReady = false;
const unsigned long OLED_REFRESH_MS = 120;

LevelConfig levels[11];
BossConfig  boss1Cfg, boss2Cfg, boss3Cfg;
GameState   currentState = STATE_MENU;

unsigned long stateTimer     = 0;
unsigned long lastFireTime   = 0;
unsigned long bossActionTimer = 0;
bool buttonsReleased         = true;
unsigned long btnWhitePressTime = 0;
bool btnWhiteHeld            = false;
unsigned long comboTimer     = 0;
bool isWaitingForCombo       = false;

std::vector<Enemy>          enemies;
std::vector<Shot>           shots;
std::vector<BossSegment>    bossSegments;
std::vector<BossProjectile> bossProjectiles;
float enemyFrontIndex = -1.0;
int   currentLevel    = 1;
int   currentBossType = 0;
int   currentScore    = 0;

const float POT_MIN_ENEMY_SPEED_MULT = 0.35;
const float POT_MAX_ENEMY_SPEED_MULT = 2.50;
const unsigned long POT_READ_INTERVAL_MS = 50;
int   potRawValue = 0;
float enemySpeedMultiplier = 1.0;

Boss2State boss2State = B2_MOVE;
int  boss2Section = 0, boss2ShotsFired = 0;
int  boss2LockedColor = 1, markerPos[3], boss2TargetShots = 10;
int  boss1WrongHits = 0;
bool boss1RageMode  = false;
int  boss1RageShots = 0;
Boss3State boss3State = B3_MOVE;
int  boss3PhaseIndex = 0, boss3BurstCounter = 0, boss3Markers[2];

unsigned long levelStartTime      = 0;
int           levelMaxPossibleScore = 0;
int           levelAchievedScore    = 0;

bool  bonusPlayedThisLevel   = false;
bool  autoBonusTrigger       = false;
int   bonusEnemiesSpawned    = 0;
int   bonusLives             = 10;
int   bonusWaveCount         = 0;
unsigned long bonusPauseTimer = 0;
bool  bonusInPause           = false;
float bonusSpeedMultiplier   = 1.0;
unsigned long bonusFlashTimer = 0;
std::vector<Enemy> bonusEnemies;
std::vector<Shot>  bonusShots;
int bonusReturnLevel = 1;

SimonState simonState = S_MOVE;
int   simonLives      = 3;
int   simonStage      = 0;
int   simonStopIndex  = 0;
float simonBossPos    = 0.0;
std::vector<int> simonFullSequence;
int   simonPlaybackIdx = 0;
int   simonInputIdx    = 0;
unsigned long simonTimer = 0;
int   simonTargetPos   = 0;

// --------------------------------------------------------------------------
// 5. COLOR HELPERS (unchanged)
// --------------------------------------------------------------------------
CRGB hexToCRGB(const char* hex) {
    long number = strtol(hex + 1, NULL, 16);
    return CRGB((number >> 16) & 0xFF, (number >> 8) & 0xFF, number & 0xFF);
}

void loadColors() {
    col_c1 = hexToCRGB("#0000FF");
    col_c2 = hexToCRGB("#FF0000");
    col_c3 = hexToCRGB("#00FF00");
    col_c4 = hexToCRGB("#FFFF00");
    col_c5 = hexToCRGB("#FF00FF");
    col_c6 = hexToCRGB("#00FFFF");
    col_cw = hexToCRGB("#FFFFFF");
    col_cb = hexToCRGB("#222222");
}

CRGB getColor(int colorCode) {
    switch (colorCode) {
        case 1: return col_c1;
        case 2: return col_c2;
        case 3: return col_c3;
        case 4: return col_c4;
        case 5: return col_c5;
        case 6: return col_c6;
        case 7: return col_cw;
        default: return CRGB::Black;
    }
}

// --------------------------------------------------------------------------
// 6. GRAPHICS HELPERS (unchanged)
// --------------------------------------------------------------------------
void drawCrispPixel(float pos, CRGB color) {
    int idx = round(pos);
    if (idx < 0 || idx >= CONFIG_NUM_LEDS) return;
    leds[idx + ledStartOffset] = color;
}

void flashPixel(int pos) {
    if (pos >= 0 && pos < CONFIG_NUM_LEDS)
        leds[pos + ledStartOffset] = CRGB::White;
}

// --------------------------------------------------------------------------
// 7. DEFAULT CONFIG (unchanged)
// --------------------------------------------------------------------------
void setupDefaultConfig() {
    levels[1]  = {5,  15, 0};
    levels[2]  = {6,  20, 0};
    levels[3]  = {7,  25, 2};
    levels[4]  = {8,  30, 0};
    levels[5]  = {9,  35, 0};
    levels[6]  = {10, 40, 1};
    levels[7]  = {20, 20, 0};
    levels[8]  = {20, 25, 0};
    levels[9]  = {10, 60, 0};
    levels[10] = {14, 60, 3};

    boss1Cfg = {4,  60, 4, 30, 0, 0,  0,  0};
    boss2Cfg = {10, 60, 5, 40, 0, 85, 55, 30};
    boss3Cfg = {7,  50, 3, 60, 3, 0,  0,  0};
}

// --------------------------------------------------------------------------
// 8. BUZZER HELPERS
//    Active buzzer: HIGH = sound, LOW = silent. Non-blocking for game logic.
// --------------------------------------------------------------------------
void queueBuzzerEvent(BuzzerEventType type) {
    if (xBuzzerQueue == NULL) return;

    BuzzerEvent event = { type };

    // Do not block the 60 FPS game task. If the buzzer queue is full,
    // the sound event is dropped but the gameplay never stalls.
    xQueueSend(xBuzzerQueue, &event, 0);
}

// --------------------------------------------------------------------------
// 9. SCORE & WIN / LOSE (unchanged logic + sound trigger only)
// --------------------------------------------------------------------------
void calculateLevelScore() {
    unsigned long duration = millis() - levelStartTime;
    int entityCount = 0;
    int calcLevel = currentLevel;
    if (currentLevel > 10) calcLevel = ((currentLevel - 1) % 10) + 1;

    if (currentLevel <= 10 && levels[currentLevel].bossType > 0) {
        if      (levels[currentLevel].bossType == 1) entityCount = 9  * boss1Cfg.hpPerLed;
        else if (levels[currentLevel].bossType == 2) entityCount = 9  * boss2Cfg.hpPerLed;
        else if (levels[currentLevel].bossType == 3) entityCount = 15 * boss3Cfg.hpPerLed;
    } else {
        entityCount = levels[calcLevel].length;
    }

    int levelMultiplier = currentLevel;
    int basePoints      = entityCount * 100 * levelMultiplier;

    unsigned long targetTime = 0;
    if (currentLevel <= 10 && levels[currentLevel].bossType == 2) {
        targetTime = 36000;
    } else {
        unsigned long travelTime     = CONFIG_NUM_LEDS * 15;
        unsigned long processingTime = entityCount * 300;
        targetTime = 3000 + travelTime + processingTime;
    }

    int timeBonus    = 0;
    int maxTimeBonus = basePoints * 3;

    if (currentLevel <= 10 && levels[currentLevel].bossType == 3) {
        timeBonus = maxTimeBonus;
    } else {
        if (duration <= targetTime) timeBonus = maxTimeBonus;
        else {
            float ratio = (float)targetTime / (float)duration;
            timeBonus   = (int)(maxTimeBonus * ratio);
        }
    }

    levelAchievedScore    = basePoints + timeBonus;
    levelMaxPossibleScore = basePoints * 4;
    currentScore         += levelAchievedScore;
}

void triggerBaseDestruction() {
    currentState = STATE_BASE_DESTROYED;
    stateTimer   = millis();
}

void checkWinCondition() {
    bool won = false;
    if (currentState == STATE_PLAYING      && enemies.empty())      won = true;
    if (currentState == STATE_BOSS_PLAYING && bossSegments.empty()) won = true;

    if (won) {
        calculateLevelScore();
        autoBonusTrigger = (levelAchievedScore >= levelMaxPossibleScore);

        // Celebration sound when any level/boss is completed.
        queueBuzzerEvent(BUZZER_EVENT_LEVEL_CLEAR);

        if (!CONFIG_ENDLESS_MODE && currentLevel >= 10) {
            currentState = STATE_GAME_FINISHED;
        } else {
            currentState = STATE_LEVEL_COMPLETED;
            stateTimer   = millis();
        }
    }
}

// --------------------------------------------------------------------------
// 9. LEVEL INTRO / START
//    CHANGED: removed FastLED.show(), digitalRead → g_buttons
// --------------------------------------------------------------------------
void drawLevelBar(int level) {
    CRGB barColor = (level <= 10 && levels[level].bossType > 0) ? col_c2 : col_c3;
    int  center   = CONFIG_NUM_LEDS / 2;
    int  displayLevel = (level > 10) ? 10 : level;
    int  totalWidth   = (displayLevel * 6) + ((displayLevel - 1) * 4);
    int  startPos     = center - (totalWidth / 2);
    if  (startPos < 0) startPos = 0;
    int cursor = startPos;
    for (int i = 0; i < displayLevel; i++) {
        for (int k = 0; k < 6; k++) {
            if (cursor < CONFIG_NUM_LEDS) leds[cursor + ledStartOffset] = barColor;
            cursor++;
        }
        cursor += 4;
    }
}

void startLevelIntro(int level) {
    if (level == CONFIG_START_LEVEL) currentScore = 0;
    if (level != currentLevel)       bonusPlayedThisLevel = false;
    currentLevel = level;
    currentState = STATE_INTRO;
    stateTimer   = millis();
    FastLED.clear();
    for (int i = 0; i < CONFIG_NUM_LEDS; i++) leds[i + ledStartOffset] = CRGB(10, 10, 10);
    drawLevelBar(level);
    if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
    // FastLED.show() removed — output task handles rendering
}

void updateLevelIntro() {
    // CHANGED: digitalRead → g_buttons (continuously updated by digital input task)
    if (!bonusPlayedThisLevel && (currentLevel <= 10 && levels[currentLevel].bossType > 0)) {
        if (g_buttons.red && g_buttons.blue && g_buttons.green) {
            bonusPlayedThisLevel = true;
            bonusReturnLevel     = currentLevel;
            currentState         = STATE_BONUS_INTRO;
            stateTimer           = millis();
            return;
        }
    }

    unsigned long elapsed = millis() - stateTimer;

    if (elapsed > 2000 && elapsed < 4000) {
        if ((elapsed / 250) % 2 == 0) {
            FastLED.clear();
            for (int i = 0; i < CONFIG_NUM_LEDS; i++) leds[i + ledStartOffset] = CRGB(5, 5, 5);
            drawLevelBar(currentLevel);
        } else {
            FastLED.clear();
        }
        if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
        // FastLED.show() removed
    } else if (elapsed <= 2000) {
        FastLED.clear();
        for (int i = 0; i < CONFIG_NUM_LEDS; i++) leds[i + ledStartOffset] = CRGB(5, 5, 5);
        drawLevelBar(currentLevel);
        if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
        // FastLED.show() removed
    }

    if (elapsed >= 4000) {
        uint8_t bright = map(CONFIG_BRIGHTNESS_PCT, 10, 100, 25, 255);
        FastLED.setBrightness(bright);
        levelStartTime = millis();

        bool isBossLevel = (currentLevel <= 10 && levels[currentLevel].bossType > 0);
        if (isBossLevel) {
            currentBossType = levels[currentLevel].bossType;
            bossSegments.clear(); enemies.clear(); shots.clear(); bossProjectiles.clear();
            enemyFrontIndex = (float)CONFIG_NUM_LEDS - 1.0;

            if (currentBossType == 1) {
                for (int i = 0; i < 3; i++) bossSegments.push_back({3, boss1Cfg.hpPerLed, boss1Cfg.hpPerLed, true, 0});
                for (int i = 0; i < 3; i++) bossSegments.push_back({1, boss1Cfg.hpPerLed, boss1Cfg.hpPerLed, true, 0});
                for (int i = 0; i < 3; i++) bossSegments.push_back({3, boss1Cfg.hpPerLed, boss1Cfg.hpPerLed, true, 0});
                bossActionTimer = millis();
                boss1WrongHits  = 0;
                boss1RageMode   = false;
            } else if (currentBossType == 2) {
                for (int i = 0; i < 9; i++) bossSegments.push_back({0, boss2Cfg.hpPerLed, boss2Cfg.hpPerLed, false, i});
                boss2Section = 0; boss2State = B2_MOVE;
                markerPos[0] = (int)(CONFIG_NUM_LEDS * (boss2Cfg.m1 / 100.0));
                markerPos[1] = (int)(CONFIG_NUM_LEDS * (boss2Cfg.m2 / 100.0));
                markerPos[2] = (int)(CONFIG_NUM_LEDS * (boss2Cfg.m3 / 100.0));
            } else if (currentBossType == 3) {
                for (int i = 0; i < 15; i++) {
                    int mixColor = random(4, 7);
                    bossSegments.push_back({mixColor, boss3Cfg.hpPerLed, boss3Cfg.hpPerLed, true, i});
                }
                boss3State      = B3_MOVE;
                boss3PhaseIndex = 0;
                boss3Markers[0] = (int)(CONFIG_NUM_LEDS * 0.66);
                boss3Markers[1] = (int)(CONFIG_NUM_LEDS * 0.50);
                bossActionTimer = millis();
            }
            currentState = STATE_BOSS_PLAYING;
        } else {
            currentBossType = 0;
            enemies.clear(); shots.clear(); bossProjectiles.clear();

            int effectiveLevel = currentLevel;
            if (currentLevel > 10) effectiveLevel = ((currentLevel - 1) % 10) + 1;
            int count = levels[effectiveLevel].length;
            if (count <= 0) count = 10;
            for (int i = 0; i < count; i++) {
                int color = (currentLevel >= 11) ? random(1, 7) : random(1, 4);
                enemies.push_back({color, 0.0, false});
            }
            enemyFrontIndex = (float)CONFIG_NUM_LEDS - 1.0;
            currentState    = STATE_PLAYING;
        }
    }
}

// --------------------------------------------------------------------------
// 10. LEVEL COMPLETED ANIMATION
//     CHANGED: removed FastLED.show()
// --------------------------------------------------------------------------
void updateLevelCompletedAnim() {
    unsigned long elapsed = millis() - stateTimer;

    if (elapsed < 1000) {
        fill_solid(leds, CONFIG_NUM_LEDS + ledStartOffset, col_c3);
        if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
    } else if (elapsed < 5000) {
        FastLED.clear();
        if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
        float pct     = (float)levelAchievedScore / (float)levelMaxPossibleScore;
        if (pct > 1.0) pct = 1.0;
        int fillLeds  = (int)(CONFIG_NUM_LEDS * pct);
        for (int i = 0; i < fillLeds; i++)              leds[i + ledStartOffset] = CRGB(80, 60, 0);
        for (int i = fillLeds; i < CONFIG_NUM_LEDS; i++) leds[i + ledStartOffset] = CRGB(20, 0, 0);
    } else {
        if (autoBonusTrigger) {
            autoBonusTrigger     = false;
            bonusPlayedThisLevel = true;
            bonusReturnLevel     = currentLevel + 1;
            currentState         = STATE_BONUS_INTRO;
            stateTimer           = millis();
        } else {
            startLevelIntro(currentLevel + 1);
        }
    }
    // FastLED.show() removed
}

// --------------------------------------------------------------------------
// 11. BASE DESTROYED ANIMATION
//     CHANGED: removed FastLED.show()
// --------------------------------------------------------------------------
void updateBaseDestroyedAnim() {
    unsigned long elapsed = millis() - stateTimer;
    if (elapsed < 2000) {
        CRGB c = (elapsed / 100) % 2 == 0 ? col_c2 : CRGB::White;
        for (int i = 0; i < CONFIG_HOMEBASE_SIZE; i++) {
            if (i + ledStartOffset < CONFIG_NUM_LEDS)
                leds[i + ledStartOffset] = c;
        }
        for (int i = CONFIG_HOMEBASE_SIZE; i < CONFIG_NUM_LEDS; i++)
            leds[i + ledStartOffset].nscale8(240);
        if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
        // FastLED.show() removed
    } else {
        currentState = STATE_GAMEOVER;
    }
}

// --------------------------------------------------------------------------
// 12. BOSS PROJECTILE MOVEMENT (unchanged)
// --------------------------------------------------------------------------
void moveBossProjectiles(float speed) {
    float step = speed / 60.0;
    if (step < 0.1) step = 0.1;
    for (int i = bossProjectiles.size() - 1; i >= 0; i--) {
        bossProjectiles[i].pos -= step;
        if (bossProjectiles[i].pos < CONFIG_HOMEBASE_SIZE) {
            triggerBaseDestruction();
        }
    }
}

// --------------------------------------------------------------------------
// 13. BONUS INTRO
//     CHANGED: removed FastLED.show()
// --------------------------------------------------------------------------
void updateBonusIntro() {
    unsigned long elapsed = millis() - stateTimer;
    if (elapsed < 2500) {
        if ((elapsed / 250) % 2 == 0) {
            FastLED.clear();
            for (int i = 0; i < CONFIG_NUM_LEDS; i += 2) leds[i + ledStartOffset] = CRGB::Yellow;
        } else {
            FastLED.clear();
        }
        if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
        // FastLED.show() removed
    } else {
        if (random(0, 100) < 50) {
            simonLives     = 3;
            simonStage     = 0;
            simonStopIndex = 0;
            simonBossPos   = (float)CONFIG_NUM_LEDS - 1.0;
            simonFullSequence.clear();
            for (int i = 0; i < 17; i++) {
                int c = (i < 8) ? random(1, 4) : random(1, 7);
                simonFullSequence.push_back(c);
            }
            currentState   = STATE_BONUS_SIMON;
            simonState     = S_MOVE;
            simonTargetPos = CONFIG_NUM_LEDS - ((simonStopIndex + 1) * (CONFIG_NUM_LEDS / 12));
        } else {
            bonusEnemiesSpawned  = 0;
            bonusLives           = 10;
            bonusWaveCount       = 0;
            bonusInPause         = false;
            bonusSpeedMultiplier = 1.0;
            bonusFlashTimer      = 0;
            bonusEnemies.clear();
            bonusShots.clear();
            lastFireTime = millis();
            currentState = STATE_BONUS_PLAYING;
        }
    }
}

// --------------------------------------------------------------------------
// 14. BONUS GAME (BEATSABER)
//     CHANGED: digitalRead → g_buttons, removed FastLED.show()
// --------------------------------------------------------------------------
void updateBonusGame() {
    unsigned long now = millis();
    bool r = g_buttons.red;      // was digitalRead(PIN_BTN_RED) == LOW
    bool g = g_buttons.green;    // was digitalRead(PIN_BTN_GREEN) == LOW
    bool pressed = (r || g);

    if (!pressed) buttonsReleased = true;
    if (pressed && buttonsReleased && (now - lastFireTime > FIRE_COOLDOWN)) {
        int c = r ? 2 : (g ? 3 : 0);
        if (c > 0) {
            bonusShots.push_back({0.0, c});
            queueBuzzerEvent(BUZZER_EVENT_SHOT);
            lastFireTime    = now;
            buttonsReleased = false;
        }
    }

    if (bonusEnemiesSpawned < 200) {
        if (bonusInPause) {
            if (now - bonusPauseTimer > 2000) {
                bonusInPause          = false;
                bonusWaveCount        = 0;
                bonusSpeedMultiplier += 0.2;
                bonusFlashTimer       = now;
            }
        } else {
            static unsigned long lastBonusSpawn = 0;
            int spawnRate = (int)(600.0 / bonusSpeedMultiplier);
            if (now - lastBonusSpawn > spawnRate) {
                lastBonusSpawn = now;
                int color = (random(0, 2) == 0) ? 2 : 3;
                bonusEnemies.push_back({color, (float)CONFIG_NUM_LEDS - 1.0, false});
                bonusEnemiesSpawned++;
                bonusWaveCount++;
                if (bonusWaveCount >= 25) {
                    bonusInPause   = true;
                    bonusPauseTimer = now;
                }
            }
        }
    }

    float shotSpeed = (float)CONFIG_SHOT_SPEED_PCT / 60.0 * 0.8;
    for (int i = bonusShots.size() - 1; i >= 0; i--) {
        bonusShots[i].position += shotSpeed;
        bool remove = false;
        for (int e = bonusEnemies.size() - 1; e >= 0; e--) {
            if (abs(bonusShots[i].position - bonusEnemies[e].pos) < 1.0) {
                if (bonusShots[i].color == bonusEnemies[e].color) {
                    bonusEnemies.erase(bonusEnemies.begin() + e);
                    currentScore += 500;
                    flashPixel((int)bonusShots[i].position);
                } else {
                    bonusLives--;
                }
                remove = true;
                break;
            }
        }
        if (!remove && bonusShots[i].position >= CONFIG_NUM_LEDS) {
            remove = true;
            bonusLives--;
        }
        if (remove) bonusShots.erase(bonusShots.begin() + i);
    }

    float enemySpeed = (25.0 / 60.0) * bonusSpeedMultiplier * enemySpeedMultiplier;
    for (int i = bonusEnemies.size() - 1; i >= 0; i--) {
        bonusEnemies[i].pos -= enemySpeed;
        if (bonusEnemies[i].pos <= CONFIG_HOMEBASE_SIZE) {
            bonusEnemies.erase(bonusEnemies.begin() + i);
            bonusLives--;
        }
    }

    if (bonusLives <= 0) {
        startLevelIntro(bonusReturnLevel);
        return;
    }
    if (bonusEnemiesSpawned >= 200 && bonusEnemies.empty()) {
        startLevelIntro(bonusReturnLevel);
        return;
    }

    FastLED.clear();
    bool doFlash = (now - bonusFlashTimer < 200) && (bonusFlashTimer > 0);
    for (auto &e : bonusEnemies) drawCrispPixel(e.pos, doFlash ? CRGB::White : getColor(e.color));
    for (auto &s : bonusShots)   drawCrispPixel(s.position, getColor(s.color));
    for (int i = 0; i < bonusLives; i++) {
        if (i + ledStartOffset < CONFIG_NUM_LEDS) leds[i + ledStartOffset] = CRGB::Yellow;
    }
    if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
    // FastLED.show() removed
}

// --------------------------------------------------------------------------
// 15. SIMON SAYS BONUS
//     CHANGED: digitalRead → g_buttons, removed FastLED.show()
// --------------------------------------------------------------------------
int getSimonStageLength(int stage) {
    int lens[] = {4, 5, 6, 8, 9, 11, 13, 15, 17};
    if (stage >= 0 && stage <= 8) return lens[stage];
    return 17;
}

void updateSimonBonus() {
    unsigned long now = millis();
    int bossLen        = 9 - simonStage;
    int currentSeqLen  = getSimonStageLength(simonStage);

    if (simonLives <= 0 || (simonState == S_MOVE && simonBossPos <= CONFIG_HOMEBASE_SIZE)) {
        startLevelIntro(bonusReturnLevel);
        return;
    }

    switch (simonState) {
        case S_MOVE: {
            float spd = 20.0 + (simonStage * 3.0);
            simonBossPos -= (spd / 60.0) * enemySpeedMultiplier;
            if (simonBossPos <= simonTargetPos) {
                simonBossPos  = (float)simonTargetPos;
                simonState    = S_PREPARE;
                simonTimer    = now;
            }
            break;
        }
        case S_PREPARE: {
            if (now - simonTimer > 1000) {
                simonState       = S_SHOW;
                simonPlaybackIdx = 0;
                simonTimer       = now;
            }
            break;
        }
        case S_SHOW: {
            int delayMs = 600 - (simonStage * 40);
            if (simonStage >= 5) delayMs = 400;
            if (simonStage >= 7) delayMs = 300;

            if (now - simonTimer > delayMs) {
                simonPlaybackIdx++;
                simonTimer = now;
                if (simonPlaybackIdx >= currentSeqLen) {
                    simonState   = S_INPUT;
                    simonInputIdx = 0;
                    buttonsReleased  = true;
                    isWaitingForCombo = false;
                }
            }
            break;
        }
        case S_INPUT: {
            // CHANGED: digitalRead → g_buttons
            bool b = g_buttons.blue;
            bool r = g_buttons.red;
            bool g = g_buttons.green;
            bool pressed = (b || r || g);

            if (!pressed) { buttonsReleased = true; isWaitingForCombo = false; }

            if (pressed && buttonsReleased && !isWaitingForCombo && (now - lastFireTime > FIRE_COOLDOWN)) {
                isWaitingForCombo = true;
                comboTimer        = now;
            }

            if (isWaitingForCombo && (now - comboTimer >= INPUT_BUFFER_MS)) {
                // Combo re-read from g_buttons (continuously updated by input task)
                b = g_buttons.blue;
                r = g_buttons.red;
                g = g_buttons.green;

                int c = 0;
                if      (r && g && b) c = 7;
                else if (r && g)      c = 4;
                else if (r && b)      c = 5;
                else if (g && b)      c = 6;
                else if (b)           c = 1;
                else if (r)           c = 2;
                else if (g)           c = 3;

                if (c > 0) {
                    if (c == simonFullSequence[simonInputIdx]) {
                        simonInputIdx++;
                        if (simonInputIdx >= currentSeqLen) {
                            simonState = S_SUCCESS;
                            simonTimer = now;
                            currentScore += (250 * (simonStage + 1));
                        }
                    } else {
                        simonState = S_FAIL;
                        simonTimer = now;
                        simonLives--;
                    }
                    lastFireTime = now;
                }
                buttonsReleased   = false;
                isWaitingForCombo = false;
            }
            break;
        }
        case S_SUCCESS: {
            if (now - simonTimer > 1000) {
                simonStage++;
                if (simonStage >= 9) {
                    startLevelIntro(bonusReturnLevel);
                    return;
                }
                simonStopIndex++;
                simonTargetPos = CONFIG_NUM_LEDS - ((simonStopIndex + 1) * (CONFIG_NUM_LEDS / 12));
                simonState     = S_MOVE;
            }
            break;
        }
        case S_FAIL: {
            if (now - simonTimer > 1000) {
                simonStopIndex++;
                simonTargetPos = CONFIG_NUM_LEDS - ((simonStopIndex + 1) * (CONFIG_NUM_LEDS / 12));
                simonState     = S_MOVE;
            }
            break;
        }
    }

    // Draw
    FastLED.clear();

    if (simonState == S_MOVE) {
        if (simonTargetPos >= 0 && simonTargetPos < CONFIG_NUM_LEDS)
            leds[simonTargetPos + ledStartOffset] = CRGB::Red;
    }

    for (int i = 0; i < bossLen; i++) {
        int pixelPos = (int)simonBossPos + i;
        if (pixelPos >= CONFIG_NUM_LEDS) continue;
        CRGB c = CRGB::Black;

        if (simonState == S_MOVE || simonState == S_PREPARE) {
            c = CHSV((i * 20) + (millis() / 10), 255, 255);
        } else if (simonState == S_SHOW) {
            if (i == 0) {
                int delayMs = 600 - (simonStage * 40);
                if (simonStage >= 5) delayMs = 400;
                if (simonStage >= 7) delayMs = 300;
                long elapsedShow = now - simonTimer;
                if (simonPlaybackIdx < currentSeqLen && elapsedShow < (delayMs - 100))
                    c = getColor(simonFullSequence[simonPlaybackIdx]);
                else
                    c = CRGB::White;
            } else {
                c = CRGB::White;
            }
        } else if (simonState == S_INPUT) {
            c = CRGB::White;
        } else if (simonState == S_SUCCESS) {
            c = (i == 0) ? (((millis() / 50) % 2 == 0) ? CRGB::Red : CRGB::Yellow) : CRGB::Green;
        } else if (simonState == S_FAIL) {
            c = CRGB::Red;
        }

        if (pixelPos >= 0) leds[pixelPos + ledStartOffset] = c;
    }

    for (int i = 0; i < simonLives; i++) {
        if (i + ledStartOffset < CONFIG_NUM_LEDS) leds[i + ledStartOffset] = CRGB::Blue;
    }
    if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
    // FastLED.show() removed
}

// --------------------------------------------------------------------------
// 16. OLED ARCADE HUD
//     CHANGED: Snapshot-based rendering for RTOS thread safety.
//     Helper functions now accept parameters instead of reading globals.
//     display.display() called inside OLED task after rendering.
// --------------------------------------------------------------------------
const char* getStateLabelFor(GameState s) {
    switch (s) {
        case STATE_MENU:            return "MENU";
        case STATE_INTRO:           return "LEVEL INTRO";
        case STATE_PLAYING:         return "WAVE ATTACK";
        case STATE_BOSS_PLAYING:    return "BOSS FIGHT";
        case STATE_LEVEL_COMPLETED: return "LEVEL CLEAR";
        case STATE_GAME_FINISHED:   return "YOU WIN!";
        case STATE_BASE_DESTROYED:  return "BASE HIT!";
        case STATE_GAMEOVER:        return "GAME OVER";
        case STATE_BONUS_INTRO:     return "BONUS READY";
        case STATE_BONUS_PLAYING:   return "BEATSABER";
        case STATE_BONUS_SIMON:     return "SIMON SAYS";
        default:                    return "UNKNOWN";
    }
}

const char* getScoreRankFor(int score) {
    if (score >= 100000) return "S+";
    if (score >= 70000)  return "S";
    if (score >= 40000)  return "A";
    if (score >= 20000)  return "B";
    if (score >= 8000)   return "C";
    return "R";
}

void drawTinyBar(int x, int y, int w, int h, int value, int maxValue) {
    if (maxValue <= 0) maxValue = 1;
    value = constrain(value, 0, maxValue);
    int fillWidth = map(value, 0, maxValue, 0, w - 2);
    display.drawRect(x, y, w, h, SSD1306_WHITE);
    display.fillRect(x + 1, y + 1, fillWidth, h - 2, SSD1306_WHITE);
}

void drawMiniHearts(int x, int y, int lives, int maxLives) {
    lives = constrain(lives, 0, maxLives);
    for (int i = 0; i < maxLives; i++) {
        int px = x + (i * 8);
        if (i < lives) {
            display.fillCircle(px, y, 2, SSD1306_WHITE);
            display.fillCircle(px + 4, y, 2, SSD1306_WHITE);
            display.fillTriangle(px - 2, y + 1, px + 6, y + 1, px + 2, y + 6, SSD1306_WHITE);
        } else {
            display.drawCircle(px, y, 2, SSD1306_WHITE);
            display.drawCircle(px + 4, y, 2, SSD1306_WHITE);
            display.drawTriangle(px - 2, y + 1, px + 6, y + 1, px + 2, y + 6, SSD1306_WHITE);
        }
    }
}

void drawSparkles() {
    int t = millis() / 120;
    for (int i = 0; i < 8; i++) {
        int x = (i * 17 + t * 3) % 128;
        int y = 14 + ((i * 11 + t * 2) % 45);
        if ((i + t) % 2 == 0) {
            display.drawPixel(x, y, SSD1306_WHITE);
            display.drawPixel(x + 1, y, SSD1306_WHITE);
            display.drawPixel(x, y + 1, SSD1306_WHITE);
        }
    }
}

void drawCenteredText(const char* txt, int y, int size) {
    int16_t x1, y1;
    uint16_t w, h;
    display.setTextSize(size);
    display.getTextBounds(txt, 0, y, &x1, &y1, &w, &h);
    int x = (SCREEN_WIDTH - w) / 2;
    if (x < 0) x = 0;
    display.setCursor(x, y);
    display.print(txt);
}

void initOLED() {
    Wire.begin(OLED_SDA, OLED_SCL);
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
        Serial.println("OLED not found. Try OLED_ADDRESS 0x3D.");
        oledReady = false;
        return;
    }
    oledReady = true;
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    drawCenteredText("ULTIMATE RGB", 8, 1);
    drawCenteredText("INVADERS", 24, 2);
    drawCenteredText("HUD ONLINE", 52, 1);
    display.display();
    delay(1200);
}

// CHANGED: renders game-over screen from snapshot score
void drawGameOverFromSnapshot(int score) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    drawCenteredText("GAME OVER", 4, 2);
    display.drawLine(0, 24, 127, 24, SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 31);
    display.print("FINAL SCORE");
    display.setCursor(0, 43);
    display.setTextSize(2);
    display.print(score);
    display.setTextSize(1);
    display.setCursor(96, 55);
    display.print("RANK ");
    display.print(getScoreRankFor(score));
    // display.display() called by OLED task
}

// CHANGED: renders win screen from snapshot score
void drawWinFromSnapshot(int score) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    drawSparkles();
    drawCenteredText("YOU WIN!", 4, 2);
    display.drawLine(0, 24, 127, 24, SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 31);
    display.print("CHAMPION SCORE");
    display.setCursor(0, 43);
    display.setTextSize(2);
    display.print(score);
    display.setTextSize(1);
    display.setCursor(96, 55);
    display.print("RANK ");
    display.print(getScoreRankFor(score));
    // display.display() called by OLED task
}

// CHANGED: full HUD render from snapshot (replaces updateOLEDHud)
void renderOledFromSnapshot(const GameSnapshot &snap) {
    if (snap.state == STATE_GAMEOVER || snap.state == STATE_BASE_DESTROYED) {
        drawGameOverFromSnapshot(snap.score);
        return;
    }
    if (snap.state == STATE_GAME_FINISHED) {
        drawWinFromSnapshot(snap.score);
        return;
    }

    // Score flash
    static int lastScore = -1;
    static unsigned long scoreFlashUntil = 0;
    unsigned long now = millis();
    if (snap.score != lastScore) {
        lastScore = snap.score;
        scoreFlashUntil = now + 450;
    }
    bool scoreFlash = now < scoreFlashUntil;

    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);

    // Top inverted title bar
    display.fillRect(0, 0, 128, 11, SSD1306_WHITE);
    display.setTextColor(SSD1306_BLACK);
    display.setTextSize(1);
    display.setCursor(2, 2);
    display.print("RGB INVADERS");
    display.setCursor(97, 2);
    display.print("L");
    display.print(snap.level);
    display.setTextColor(SSD1306_WHITE);

    // Score area
    display.setCursor(0, 15);
    display.setTextSize(1);
    if (scoreFlash) {
        display.print("SCORE BOOST!");
        drawSparkles();
    } else {
        display.print("SCORE");
    }

    display.setCursor(0, 25);
    if (snap.score < 100000) display.setTextSize(2);
    else display.setTextSize(1);
    display.print(snap.score);

    // Rank badge
    display.drawRoundRect(89, 16, 37, 23, 4, SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(95, 19);
    display.print("RANK");
    display.setCursor(101, 30);
    display.print(getScoreRankFor(snap.score));

    // Mode line
    display.setTextSize(1);
    display.setCursor(0, 42);
    display.print(getStateLabelFor(snap.state));

    // Smart progress area
    int barValue = 0;
    int barMax = 100;
    const char* barLabel = "READY";

    if (snap.state == STATE_PLAYING) {
        barValue = snap.totalLevelEnemies - snap.enemiesRemaining;
        barMax   = snap.totalLevelEnemies;
        barLabel = "WAVE";
    }
    else if (snap.state == STATE_BOSS_PLAYING) {
        barValue = snap.bossHpMax - snap.bossHpCurrent;
        barMax   = snap.bossHpMax;
        barLabel = "BOSS";
    }
    else if (snap.state == STATE_LEVEL_COMPLETED) {
        barValue = snap.lvlAchievedScore;
        barMax   = snap.lvlMaxPossibleScore;
        barLabel = "CLEAR";
    }
    else if (snap.state == STATE_BONUS_PLAYING) {
        barValue = snap.bonusSpawned;
        barMax   = 200;
        barLabel = "BONUS";
        display.setCursor(83, 43);
        display.print("HP ");
        display.print(snap.bonusLivesVal);
    }
    else if (snap.state == STATE_BONUS_SIMON) {
        barValue = snap.simonStageVal + 1;
        barMax   = 9;
        barLabel = "SIMON";
        drawMiniHearts(84, 44, snap.simonLivesVal, 3);
    }
    else if (snap.state == STATE_INTRO) {
        unsigned long introElapsed = now - snap.stateTimerVal;
        barValue = constrain((int)introElapsed, 0, 4000);
        barMax   = 4000;
        barLabel = "START";
    }
    else if (snap.state == STATE_BONUS_INTRO) {
        unsigned long bonusElapsed = now - snap.stateTimerVal;
        barValue = constrain((int)bonusElapsed, 0, 2500);
        barMax   = 2500;
        barLabel = "BONUS";
    }

    display.setCursor(0, 55);
    display.setTextSize(1);
    display.print(barLabel);
    drawTinyBar(38, 54, 88, 8, barValue, barMax);

    // display.display() called by OLED task after this returns
}

// -------------------------------------------------------------------------- // AFTER UPDATE
// 17. TELEMETRY + WIFI DASHBOARD SYSTEM // AFTER UPDATE
// -------------------------------------------------------------------------- // AFTER UPDATE
void onWebSocketEvent(uint8_t clientId, WStype_t type, uint8_t *payload, size_t length); // AFTER UPDATE
void setupWiFi() { // AFTER UPDATE
    WiFi.mode(WIFI_STA); // AFTER UPDATE
    WiFi.setSleep(false); // AFTER UPDATE
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD); // AFTER UPDATE
    telemetryWiFiRetryTimer = millis(); // AFTER UPDATE
    Serial.println(); // AFTER UPDATE
    Serial.print("WiFi telemetry connecting in background to SSID: "); // AFTER UPDATE
    Serial.println(WIFI_SSID); // AFTER UPDATE
} // AFTER UPDATE

void handleTelemetryWiFi() { // AFTER UPDATE
    wl_status_t wifiStatus = WiFi.status(); // AFTER UPDATE
    unsigned long now = millis(); // AFTER UPDATE
    if (wifiStatus == WL_CONNECTED) { // AFTER UPDATE
        if (telemetryWiFiConnectedAt == 0) telemetryWiFiConnectedAt = now; // AFTER UPDATE
        if (!telemetryWiFiConnectedPrinted) { // AFTER UPDATE
            telemetryWiFiConnectedPrinted = true; // AFTER UPDATE
            Serial.print("WiFi connected. ESP32 IP: "); // AFTER UPDATE
            Serial.println(WiFi.localIP()); // AFTER UPDATE
        } // AFTER UPDATE
        if (!telemetryWebSocketStarted && (now - telemetryWiFiConnectedAt >= 2000)) { // AFTER UPDATE
            webSocket.begin(); // AFTER UPDATE
            webSocket.onEvent(onWebSocketEvent); // AFTER UPDATE
            webSocket.enableHeartbeat(15000, 3000, 2); // AFTER UPDATE
            telemetryWebSocketStarted = true; // AFTER UPDATE
            Serial.println("WebSocket telemetry port: 81"); // AFTER UPDATE
        } // AFTER UPDATE
        return; // AFTER UPDATE
    } // AFTER UPDATE

    telemetryWiFiConnectedAt = 0; // AFTER UPDATE
    telemetryWiFiConnectedPrinted = false; // AFTER UPDATE
    if (now - telemetryWiFiRetryTimer >= WIFI_RETRY_INTERVAL_MS) { // AFTER UPDATE
        telemetryWiFiRetryTimer = now; // AFTER UPDATE
        Serial.print("WiFi not connected. status="); // AFTER UPDATE
        Serial.print((int)wifiStatus); // AFTER UPDATE
        Serial.println(" | retrying in background..."); // AFTER UPDATE
        WiFi.disconnect(); // AFTER UPDATE
        WiFi.begin(WIFI_SSID, WIFI_PASSWORD); // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

void onWebSocketEvent(uint8_t clientId, WStype_t type, uint8_t *payload, size_t length) { // AFTER UPDATE
    (void)payload; // AFTER UPDATE
    (void)length; // AFTER UPDATE
    if (type == WStype_CONNECTED) { // AFTER UPDATE
        IPAddress ip = webSocket.remoteIP(clientId); // AFTER UPDATE
        Serial.printf("[WS] Client %u connected from %u.%u.%u.%u\n", clientId, ip[0], ip[1], ip[2], ip[3]); // AFTER UPDATE
    } // AFTER UPDATE
    else if (type == WStype_DISCONNECTED) { // AFTER UPDATE
        Serial.printf("[WS] Client %u disconnected\n", clientId); // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

String getGameStateNameFrom(GameState stateValue) { // AFTER UPDATE
    switch (stateValue) { // AFTER UPDATE
        case STATE_MENU: return "MENU"; // AFTER UPDATE
        case STATE_INTRO: return "INTRO"; // AFTER UPDATE
        case STATE_PLAYING: return "PLAYING"; // AFTER UPDATE
        case STATE_BOSS_PLAYING: return "BOSS"; // AFTER UPDATE
        case STATE_LEVEL_COMPLETED: return "LEVEL_COMPLETE"; // AFTER UPDATE
        case STATE_GAME_FINISHED: return "FINISHED"; // AFTER UPDATE
        case STATE_BASE_DESTROYED: return "BASE_DESTROYED"; // AFTER UPDATE
        case STATE_GAMEOVER: return "GAME_OVER"; // AFTER UPDATE
        case STATE_BONUS_INTRO: return "BONUS_INTRO"; // AFTER UPDATE
        case STATE_BONUS_PLAYING: return "BEAT_SABER"; // AFTER UPDATE
        case STATE_BONUS_SIMON: return "SIMON"; // AFTER UPDATE
        default: return "UNKNOWN"; // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

String getGameStateName() { // AFTER UPDATE
    return getGameStateNameFrom(currentState); // AFTER UPDATE
} // AFTER UPDATE

String getTelemetryModeName(GameState stateValue, int bossTypeValue) { // AFTER UPDATE
    if (stateValue == STATE_BONUS_PLAYING) return "BEAT_SABER"; // AFTER UPDATE
    if (stateValue == STATE_BONUS_SIMON) return "SIMON"; // AFTER UPDATE
    if (stateValue == STATE_BOSS_PLAYING && bossTypeValue == 3) return "FINAL_BOSS"; // AFTER UPDATE
    if (stateValue == STATE_BOSS_PLAYING) return "BOSS"; // AFTER UPDATE
    return "NORMAL"; // AFTER UPDATE
} // AFTER UPDATE

int calculateBossHP() { // AFTER UPDATE
    int hp = 0; // AFTER UPDATE
    for (size_t i = 0; i < bossSegments.size(); i++) { // AFTER UPDATE
        hp += bossSegments[i].hp; // AFTER UPDATE
    } // AFTER UPDATE
    return hp; // AFTER UPDATE
} // AFTER UPDATE

int calculateMaxBossHP() { // AFTER UPDATE
    int hp = 0; // AFTER UPDATE
    for (size_t i = 0; i < bossSegments.size(); i++) { // AFTER UPDATE
        hp += bossSegments[i].maxHp; // AFTER UPDATE
    } // AFTER UPDATE
    return hp; // AFTER UPDATE
} // AFTER UPDATE

int getCurrentComboColorTelemetry() { // AFTER UPDATE
    bool b = g_buttons.blue; // AFTER UPDATE
    bool r = g_buttons.red; // AFTER UPDATE
    bool g = g_buttons.green; // AFTER UPDATE
    if (r && g && b) return 7; // AFTER UPDATE
    if (r && g) return 4; // AFTER UPDATE
    if (r && b) return 5; // AFTER UPDATE
    if (g && b) return 6; // AFTER UPDATE
    if (b) return 1; // AFTER UPDATE
    if (r) return 2; // AFTER UPDATE
    if (g) return 3; // AFTER UPDATE
    return 0; // AFTER UPDATE
} // AFTER UPDATE

int calculatePlayerAccuracyTelemetry(const GameSnapshot &snap) { // AFTER UPDATE
    if (snap.lvlMaxPossibleScore <= 0) return 0; // AFTER UPDATE
    long value = ((long)snap.lvlAchievedScore * 100L) / (long)snap.lvlMaxPossibleScore; // AFTER UPDATE
    if (value < 0) value = 0; // AFTER UPDATE
    if (value > 100) value = 100; // AFTER UPDATE
    return (int)value; // AFTER UPDATE
} // AFTER UPDATE

uint8_t getLedColorIdTelemetry(const CRGB &color) { // AFTER UPDATE
    uint8_t r = color.r; // AFTER UPDATE
    uint8_t g = color.g; // AFTER UPDATE
    uint8_t b = color.b; // AFTER UPDATE
    if (r < 20 && g < 20 && b < 20) return 0; // AFTER UPDATE
    if (r > 180 && g > 180 && b > 180) return 7; // AFTER UPDATE
    if (r > 120 && g > 120 && b < 100) return 4; // AFTER UPDATE
    if (r > 120 && b > 120 && g < 100) return 5; // AFTER UPDATE
    if (g > 120 && b > 120 && r < 100) return 6; // AFTER UPDATE
    if (b >= r && b >= g) return 1; // AFTER UPDATE
    if (r >= g && r >= b) return 2; // AFTER UPDATE
    if (g >= r && g >= b) return 3; // AFTER UPDATE
    return 0; // AFTER UPDATE
} // AFTER UPDATE

int getTelemetryLedCount() { // AFTER UPDATE
    int count = CONFIG_NUM_LEDS; // AFTER UPDATE
    if (count < 0) count = 0; // AFTER UPDATE
    if (count > MAX_LEDS) count = MAX_LEDS; // AFTER UPDATE
    return count; // AFTER UPDATE
} // AFTER UPDATE

void updateTelemetryLedMirror() { // AFTER UPDATE
    if (xTelemetryMutex == NULL) return; // AFTER UPDATE
    if (xSemaphoreTake(xTelemetryMutex, 0) != pdTRUE) return; // AFTER UPDATE
    int ledCountForTelemetry = getTelemetryLedCount(); // AFTER UPDATE
    for (int i = 0; i < ledCountForTelemetry; i++) { // AFTER UPDATE
        int sourceLedIndex = i + ledStartOffset; // AFTER UPDATE
        if (sourceLedIndex >= MAX_LEDS) break; // AFTER UPDATE
        telemetryLedMirror[i] = getLedColorIdTelemetry(leds[sourceLedIndex]); // AFTER UPDATE
    } // AFTER UPDATE
    xSemaphoreGive(xTelemetryMutex); // AFTER UPDATE
} // AFTER UPDATE

bool copyTelemetryLedMirrorForPacket(int ledCountForTelemetry) { // AFTER UPDATE
    if (xTelemetryMutex == NULL) return false; // AFTER UPDATE
    if (xSemaphoreTake(xTelemetryMutex, pdMS_TO_TICKS(2)) != pdTRUE) return false; // AFTER UPDATE
    for (int i = 0; i < ledCountForTelemetry; i++) { // AFTER UPDATE
        telemetryLedPacket[i] = telemetryLedMirror[i]; // AFTER UPDATE
    } // AFTER UPDATE
    xSemaphoreGive(xTelemetryMutex); // AFTER UPDATE
    return true; // AFTER UPDATE
} // AFTER UPDATE

void sendTelemetry() { // AFTER UPDATE
    if (WiFi.status() != WL_CONNECTED) return; // AFTER UPDATE
    if (!telemetryWebSocketStarted) return; // AFTER UPDATE
    GameSnapshot snap; // AFTER UPDATE
    if (xSemaphoreTake(xSnapshotMutex, pdMS_TO_TICKS(2)) == pdTRUE) { // AFTER UPDATE
        snap = g_snapshot; // AFTER UPDATE
        xSemaphoreGive(xSnapshotMutex); // AFTER UPDATE
    } else { // AFTER UPDATE
        return; // AFTER UPDATE
    } // AFTER UPDATE

    int ledCountForTelemetry = getTelemetryLedCount(); // AFTER UPDATE
    if (!copyTelemetryLedMirrorForPacket(ledCountForTelemetry)) return; // AFTER UPDATE

    telemetry.level = snap.level; // AFTER UPDATE
    telemetry.score = snap.score; // AFTER UPDATE
    telemetry.enemiesRemaining = snap.enemiesRemaining; // AFTER UPDATE
    telemetry.bossHP = (snap.state == STATE_BOSS_PLAYING) ? snap.bossHpCurrent : 0; // AFTER UPDATE
    telemetry.maxBossHP = (snap.state == STATE_BOSS_PLAYING) ? snap.bossHpMax : 0; // AFTER UPDATE
    telemetry.gameState = getGameStateNameFrom(snap.state); // AFTER UPDATE
    telemetry.comboColor = snap.comboColorVal; // AFTER UPDATE
    telemetry.playerAccuracy = calculatePlayerAccuracyTelemetry(snap); // AFTER UPDATE
    telemetry.activeProjectiles = snap.activeProjectiles; // AFTER UPDATE
    telemetry.simonStage = snap.simonStageVal; // AFTER UPDATE
    telemetry.beatSaberMode = (snap.state == STATE_BONUS_PLAYING); // AFTER UPDATE
    telemetry.simonMode = (snap.state == STATE_BONUS_SIMON); // AFTER UPDATE

    telemetryJsonPacket = ""; // AFTER UPDATE
    telemetryJsonPacket.reserve(TELEMETRY_JSON_RESERVE_BYTES); // AFTER UPDATE
    telemetryJsonPacket += "{\"type\":\"telemetry\",\"level\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.level; // AFTER UPDATE
    telemetryJsonPacket += ",\"score\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.score; // AFTER UPDATE
    telemetryJsonPacket += ",\"bossHP\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.bossHP; // AFTER UPDATE
    telemetryJsonPacket += ",\"maxBossHP\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.maxBossHP; // AFTER UPDATE
    telemetryJsonPacket += ",\"enemies\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.enemiesRemaining; // AFTER UPDATE
    telemetryJsonPacket += ",\"state\":\""; // AFTER UPDATE
    telemetryJsonPacket += telemetry.gameState; // AFTER UPDATE
    telemetryJsonPacket += "\",\"projectiles\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.activeProjectiles; // AFTER UPDATE
    telemetryJsonPacket += ",\"accuracy\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.playerAccuracy; // AFTER UPDATE
    telemetryJsonPacket += ",\"comboColor\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.comboColor; // AFTER UPDATE
    telemetryJsonPacket += ",\"mode\":\""; // AFTER UPDATE
    telemetryJsonPacket += getTelemetryModeName(snap.state, snap.currentBossTypeVal); // AFTER UPDATE
    telemetryJsonPacket += "\",\"simonStage\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.simonStage; // AFTER UPDATE
    telemetryJsonPacket += ",\"beatSaber\":"; // AFTER UPDATE
    telemetryJsonPacket += telemetry.beatSaberMode ? "true" : "false"; // AFTER UPDATE
    telemetryJsonPacket += ",\"ledCount\":"; // AFTER UPDATE
    telemetryJsonPacket += ledCountForTelemetry; // AFTER UPDATE
    telemetryJsonPacket += ",\"timestamp\":"; // AFTER UPDATE
    telemetryJsonPacket += millis(); // AFTER UPDATE
    telemetryJsonPacket += ",\"leds\":["; // AFTER UPDATE

    for (int i = 0; i < ledCountForTelemetry; i++) { // AFTER UPDATE
        if (i > 0) telemetryJsonPacket += ','; // AFTER UPDATE
        telemetryJsonPacket += (int)telemetryLedPacket[i]; // AFTER UPDATE
    } // AFTER UPDATE
    telemetryJsonPacket += "]}"; // AFTER UPDATE

    webSocket.broadcastTXT(telemetryJsonPacket); // AFTER UPDATE
    telemetryPacketsSent++; // AFTER UPDATE
} // AFTER UPDATE

// -------------------------------------------------------------------------- // AFTER UPDATE
// 17a. EVENT STREAMING & BUG REPORTING HELPERS // AFTER UPDATE
// -------------------------------------------------------------------------- // AFTER UPDATE

const char* getEventName(TelemetryEventType t) { // AFTER UPDATE
    switch (t) { // AFTER UPDATE
        case EVT_STATE_CHANGE:            return "STATE_CHANGE"; // AFTER UPDATE
        case EVT_LEVEL_COMPLETED:         return "LEVEL_COMPLETED"; // AFTER UPDATE
        case EVT_BOSS_SPAWNED:            return "BOSS_SPAWNED"; // AFTER UPDATE
        case EVT_BOSS_SEGMENT_DESTROYED:  return "BOSS_SEG_DESTROYED"; // AFTER UPDATE
        case EVT_ENEMY_DESTROYED:         return "ENEMY_DESTROYED"; // AFTER UPDATE
        case EVT_COMBO_TRIGGERED:         return "COMBO_TRIGGERED"; // AFTER UPDATE
        case EVT_COMBO_FAILED:            return "COMBO_FAILED"; // AFTER UPDATE
        case EVT_SIMON_STARTED:           return "SIMON_STARTED"; // AFTER UPDATE
        case EVT_SIMON_COMPLETED:         return "SIMON_COMPLETED"; // AFTER UPDATE
        case EVT_BEATSABER_STARTED:       return "BEATSABER_STARTED"; // AFTER UPDATE
        case EVT_BEATSABER_COMPLETED:     return "BEATSABER_COMPLETED"; // AFTER UPDATE
        case EVT_GAME_OVER:               return "GAME_OVER"; // AFTER UPDATE
        case EVT_GAME_WON:                return "GAME_WON"; // AFTER UPDATE
        case EVT_BASE_DESTROYED:          return "BASE_DESTROYED"; // AFTER UPDATE
        default:                          return "UNKNOWN"; // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

const char* getBugName(BugType t) { // AFTER UPDATE
    switch (t) { // AFTER UPDATE
        case BUG_NEGATIVE_HP:          return "NEGATIVE_HP"; // AFTER UPDATE
        case BUG_NEGATIVE_SCORE:       return "NEGATIVE_SCORE"; // AFTER UPDATE
        case BUG_INVALID_STATE:        return "INVALID_STATE"; // AFTER UPDATE
        case BUG_ACCURACY_OVERFLOW:    return "ACCURACY_OVERFLOW"; // AFTER UPDATE
        case BUG_ENEMY_COUNT_NEGATIVE: return "ENEMY_COUNT_NEGATIVE"; // AFTER UPDATE
        case BUG_LEVEL_OVERFLOW:       return "LEVEL_OVERFLOW"; // AFTER UPDATE
        case BUG_IMPOSSIBLE_COMBO:     return "IMPOSSIBLE_COMBO"; // AFTER UPDATE
        case BUG_TELEMETRY_FAILURE:    return "TELEMETRY_FAILURE"; // AFTER UPDATE
        case BUG_TASK_STALL:           return "TASK_STALL"; // AFTER UPDATE
        default:                       return "UNKNOWN"; // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

const char* getSeverityName(BugSeverity s) { // AFTER UPDATE
    switch (s) { // AFTER UPDATE
        case BUG_LOW:      return "LOW"; // AFTER UPDATE
        case BUG_MEDIUM:   return "MEDIUM"; // AFTER UPDATE
        case BUG_HIGH:     return "HIGH"; // AFTER UPDATE
        case BUG_CRITICAL: return "CRITICAL"; // AFTER UPDATE
        default:           return "UNKNOWN"; // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

void pushEvent(TelemetryEventType type, int val1 = 0, int val2 = 0) { // AFTER UPDATE
    if (xEventQueue == NULL) return; // AFTER UPDATE
    TelemetryEvent evt; // AFTER UPDATE
    evt.type = type; // AFTER UPDATE
    evt.timestamp = millis(); // AFTER UPDATE
    evt.level = currentLevel; // AFTER UPDATE
    evt.value1 = val1; // AFTER UPDATE
    evt.value2 = val2; // AFTER UPDATE
    xQueueSend(xEventQueue, &evt, 0); // AFTER UPDATE
} // AFTER UPDATE

void pushBug(BugType type, BugSeverity severity, int val1 = 0) { // AFTER UPDATE
    if (xBugQueue == NULL) return; // AFTER UPDATE
    BugReport bug; // AFTER UPDATE
    bug.type = type; // AFTER UPDATE
    bug.severity = severity; // AFTER UPDATE
    bug.timestamp = millis(); // AFTER UPDATE
    bug.level = currentLevel; // AFTER UPDATE
    bug.value1 = val1; // AFTER UPDATE
    xQueueSend(xBugQueue, &bug, 0); // AFTER UPDATE
    g_assertionFailures++; // AFTER UPDATE
} // AFTER UPDATE

// Lightweight runtime assertion macro (non-blocking) // AFTER UPDATE
#define TELEM_ASSERT(cond, bugType, severity, val) \
    do { if (!(cond)) pushBug(bugType, severity, val); } while(0) // AFTER UPDATE

void sendEventPacket(const TelemetryEvent &evt) { // AFTER UPDATE
    if (!telemetryWebSocketStarted || WiFi.status() != WL_CONNECTED) return; // AFTER UPDATE
    if (webSocket.connectedClients() == 0) return; // AFTER UPDATE
    String pkt; // AFTER UPDATE
    pkt.reserve(256); // AFTER UPDATE
    pkt += "{\"type\":\"event\",\"event\":\""; // AFTER UPDATE
    pkt += getEventName(evt.type); // AFTER UPDATE
    pkt += "\",\"timestamp\":"; // AFTER UPDATE
    pkt += evt.timestamp; // AFTER UPDATE
    pkt += ",\"level\":"; // AFTER UPDATE
    pkt += evt.level; // AFTER UPDATE
    pkt += ",\"value1\":"; // AFTER UPDATE
    pkt += evt.value1; // AFTER UPDATE
    pkt += ",\"value2\":"; // AFTER UPDATE
    pkt += evt.value2; // AFTER UPDATE
    pkt += "}"; // AFTER UPDATE
    webSocket.broadcastTXT(pkt); // AFTER UPDATE
} // AFTER UPDATE

void sendBugPacket(const BugReport &bug) { // AFTER UPDATE
    if (!telemetryWebSocketStarted || WiFi.status() != WL_CONNECTED) return; // AFTER UPDATE
    if (webSocket.connectedClients() == 0) return; // AFTER UPDATE
    String pkt; // AFTER UPDATE
    pkt.reserve(256); // AFTER UPDATE
    pkt += "{\"type\":\"bug\",\"severity\":\""; // AFTER UPDATE
    pkt += getSeverityName(bug.severity); // AFTER UPDATE
    pkt += "\",\"bug\":\""; // AFTER UPDATE
    pkt += getBugName(bug.type); // AFTER UPDATE
    pkt += "\",\"timestamp\":"; // AFTER UPDATE
    pkt += bug.timestamp; // AFTER UPDATE
    pkt += ",\"state\":\""; // AFTER UPDATE
    pkt += getGameStateName(); // AFTER UPDATE
    pkt += "\",\"level\":"; // AFTER UPDATE
    pkt += bug.level; // AFTER UPDATE
    pkt += ",\"value\":"; // AFTER UPDATE
    pkt += bug.value1; // AFTER UPDATE
    pkt += "}"; // AFTER UPDATE
    webSocket.broadcastTXT(pkt); // AFTER UPDATE
} // AFTER UPDATE

void sendDiagnosticsPacket() { // AFTER UPDATE
    if (!telemetryWebSocketStarted || WiFi.status() != WL_CONNECTED) return; // AFTER UPDATE
    if (webSocket.connectedClients() == 0) return; // AFTER UPDATE
    String pkt; // AFTER UPDATE
    pkt.reserve(512); // AFTER UPDATE
    pkt += "{\"type\":\"diagnostics\",\"timestamp\":"; // AFTER UPDATE
    pkt += millis(); // AFTER UPDATE
    pkt += ",\"fps\":"; // AFTER UPDATE
    pkt += (int)g_currentFPS; // AFTER UPDATE
    pkt += ",\"frameTimeUs\":"; // AFTER UPDATE
    pkt += g_lastFrameTimeUs; // AFTER UPDATE
    pkt += ",\"heap\":"; // AFTER UPDATE
    pkt += (int)esp_get_free_heap_size(); // AFTER UPDATE
    pkt += ",\"minHeap\":"; // AFTER UPDATE
    pkt += (int)esp_get_minimum_free_heap_size(); // AFTER UPDATE
    pkt += ",\"wifiRssi\":"; // AFTER UPDATE
    pkt += WiFi.RSSI(); // AFTER UPDATE
    pkt += ",\"wsClients\":"; // AFTER UPDATE
    pkt += webSocket.connectedClients(); // AFTER UPDATE
    pkt += ",\"packetsSent\":"; // AFTER UPDATE
    pkt += telemetryPacketsSent; // AFTER UPDATE
    pkt += ",\"assertions\":"; // AFTER UPDATE
    pkt += g_assertionFailures; // AFTER UPDATE
    pkt += ",\"tasks\":["; // AFTER UPDATE
    for (int i = 0; i < TASK_COUNT; i++) { // AFTER UPDATE
        if (i > 0) pkt += ','; // AFTER UPDATE
        pkt += "{\"name\":\""; // AFTER UPDATE
        pkt += (g_taskHeartbeats[i].name ? g_taskHeartbeats[i].name : "?"); // AFTER UPDATE
        pkt += "\",\"lastBeat\":"; // AFTER UPDATE
        pkt += g_taskHeartbeats[i].lastBeat; // AFTER UPDATE
        pkt += ",\"maxMs\":"; // AFTER UPDATE
        pkt += g_taskHeartbeats[i].maxIntervalMs; // AFTER UPDATE
        pkt += "}"; // AFTER UPDATE
    } // AFTER UPDATE
    pkt += "]}"; // AFTER UPDATE
    webSocket.broadcastTXT(pkt); // AFTER UPDATE
} // AFTER UPDATE

void updateTaskHeartbeat(int taskIndex) { // AFTER UPDATE
    if (taskIndex < 0 || taskIndex >= TASK_COUNT) return; // AFTER UPDATE
    unsigned long now = millis(); // AFTER UPDATE
    unsigned long prev = g_taskHeartbeats[taskIndex].lastBeat; // AFTER UPDATE
    if (prev > 0) { // AFTER UPDATE
        unsigned long interval = now - prev; // AFTER UPDATE
        if (interval > g_taskHeartbeats[taskIndex].maxIntervalMs) { // AFTER UPDATE
            g_taskHeartbeats[taskIndex].maxIntervalMs = interval; // AFTER UPDATE
        } // AFTER UPDATE
    } // AFTER UPDATE
    g_taskHeartbeats[taskIndex].lastBeat = now; // AFTER UPDATE
} // AFTER UPDATE

void checkStateTransitionEvents() { // AFTER UPDATE
    if (currentState != g_prevState) { // AFTER UPDATE
        pushEvent(EVT_STATE_CHANGE, (int)g_prevState, (int)currentState); // AFTER UPDATE
        if (currentState == STATE_GAMEOVER) pushEvent(EVT_GAME_OVER, currentScore); // AFTER UPDATE
        if (currentState == STATE_GAME_FINISHED) pushEvent(EVT_GAME_WON, currentScore); // AFTER UPDATE
        if (currentState == STATE_BASE_DESTROYED) pushEvent(EVT_BASE_DESTROYED); // AFTER UPDATE
        if (currentState == STATE_BOSS_PLAYING && g_prevState != STATE_BOSS_PLAYING) { // AFTER UPDATE
            pushEvent(EVT_BOSS_SPAWNED, currentBossType); // AFTER UPDATE
        } // AFTER UPDATE
        if (currentState == STATE_BONUS_PLAYING && g_prevState != STATE_BONUS_PLAYING) { // AFTER UPDATE
            pushEvent(EVT_BEATSABER_STARTED); // AFTER UPDATE
        } // AFTER UPDATE
        if (currentState == STATE_BONUS_SIMON && g_prevState != STATE_BONUS_SIMON) { // AFTER UPDATE
            pushEvent(EVT_SIMON_STARTED); // AFTER UPDATE
        } // AFTER UPDATE
        if (currentState == STATE_LEVEL_COMPLETED) { // AFTER UPDATE
            pushEvent(EVT_LEVEL_COMPLETED, levelAchievedScore, levelMaxPossibleScore); // AFTER UPDATE
        } // AFTER UPDATE
        g_prevState = currentState; // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

void runTelemetryAssertions() { // AFTER UPDATE
    TELEM_ASSERT(currentScore >= 0, BUG_NEGATIVE_SCORE, BUG_HIGH, currentScore); // AFTER UPDATE
    TELEM_ASSERT(currentLevel >= 1 && currentLevel <= 100, BUG_LEVEL_OVERFLOW, BUG_MEDIUM, currentLevel); // AFTER UPDATE
    TELEM_ASSERT((int)enemies.size() >= 0, BUG_ENEMY_COUNT_NEGATIVE, BUG_HIGH, (int)enemies.size()); // AFTER UPDATE
    if (currentState == STATE_BOSS_PLAYING) { // AFTER UPDATE
        for (const auto &seg : bossSegments) { // AFTER UPDATE
            TELEM_ASSERT(seg.hp >= 0, BUG_NEGATIVE_HP, BUG_HIGH, seg.hp); // AFTER UPDATE
        } // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

// --------------------------------------------------------------------------
// 17. SNAPSHOT UPDATE (NEW)
//     Called at end of each game frame to safely expose state to OLED/Log.
// --------------------------------------------------------------------------
void takeGameSnapshot() {
    xSemaphoreTake(xSnapshotMutex, portMAX_DELAY);

    g_snapshot.state              = currentState;
    g_snapshot.level              = currentLevel;
    g_snapshot.score              = currentScore;
    g_snapshot.currentBossTypeVal = currentBossType; // AFTER UPDATE
    g_snapshot.comboColorVal      = getCurrentComboColorTelemetry(); // AFTER UPDATE
    g_snapshot.enemiesRemaining   = enemies.size();

    int mapLevel = currentLevel;
    if (currentLevel > 10) mapLevel = ((currentLevel - 1) % 10) + 1;
    g_snapshot.totalLevelEnemies  = levels[mapLevel].length;

    int hpNow = 0, hpMax = 0;
    for (auto &seg : bossSegments) { hpNow += seg.hp; hpMax += seg.maxHp; }
    if (hpMax <= 0) hpMax = 1;
    g_snapshot.bossHpCurrent      = hpNow;
    g_snapshot.bossHpMax          = hpMax;
    g_snapshot.activeProjectiles  = shots.size() + bossProjectiles.size() + bonusShots.size(); // AFTER UPDATE

    g_snapshot.lvlAchievedScore   = levelAchievedScore;
    g_snapshot.lvlMaxPossibleScore = levelMaxPossibleScore;
    g_snapshot.bonusSpawned       = bonusEnemiesSpawned;
    g_snapshot.bonusLivesVal      = bonusLives;
    g_snapshot.simonStageVal      = simonStage;
    g_snapshot.simonLivesVal      = simonLives;
    g_snapshot.stateTimerVal      = stateTimer;

    xSemaphoreGive(xSnapshotMutex);
}

// --------------------------------------------------------------------------
// 18. BUTTON ISR (NEW)
// --------------------------------------------------------------------------
void IRAM_ATTR onButtonISR() {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    xSemaphoreGiveFromISR(xButtonISRSem, &xHigherPriorityTaskWoken);
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

// --------------------------------------------------------------------------
// 19. RTOS TASKS (NEW)
// --------------------------------------------------------------------------

// --- Task 1: Analog Sensor (Potentiometer ADC) ---
void vAnalogSensorTask(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    for (;;) {
        updateTaskHeartbeat(0); // AFTER UPDATE
        int rawVal = analogRead(POT_PIN);
        // Timeout-based queue send (satisfies RTOS timeout requirement)
        xQueueSend(xPotQueue, &rawVal, pdMS_TO_TICKS(10));
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(POT_READ_INTERVAL_MS));
    }
}

// --- Task 2: Digital Input (Buttons via ISR + poll fallback) ---
void vDigitalInputTask(void *pvParameters) {
    for (;;) {
        updateTaskHeartbeat(1); // AFTER UPDATE
        // Wait for button ISR or poll every 10 ms (timeout-based semaphore take)
        xSemaphoreTake(xButtonISRSem, pdMS_TO_TICKS(10));

        ButtonState bs;
        bs.blue  = (digitalRead(PIN_BTN_BLUE)  == LOW);
        bs.red   = (digitalRead(PIN_BTN_RED)   == LOW);
        bs.green = (digitalRead(PIN_BTN_GREEN) == LOW);
        bs.white = (digitalRead(PIN_BTN_WHITE) == LOW);

        xSemaphoreTake(xInputMutex, portMAX_DELAY);
        g_buttons = bs;
        xSemaphoreGive(xInputMutex);
    }
}

// --- Task 3: Game Processing (main state machine) ---
void vGameProcessingTask(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();

    for (;;) {
        // --- Receive pot data from queue (drain to latest) ---
        int potRaw;
        while (xQueueReceive(xPotQueue, &potRaw, 0) == pdPASS) {
            potRawValue = potRaw;
            float rawRatio = (float)potRawValue / 4095.0;
            if (rawRatio < 0.0) rawRatio = 0.0;
            if (rawRatio > 1.0) rawRatio = 1.0;
            enemySpeedMultiplier = POT_MIN_ENEMY_SPEED_MULT +
                (rawRatio * (POT_MAX_ENEMY_SPEED_MULT - POT_MIN_ENEMY_SPEED_MULT));
        }

        unsigned long now = millis();

        // --- WHITE BUTTON: short press = restart ---
        // Read latest button state for white button check
        bool wBtn = g_buttons.white;
        if (wBtn) {
            if (!btnWhiteHeld) { btnWhiteHeld = true; btnWhitePressTime = now; }
        } else {
            if (btnWhiteHeld) {
                unsigned long holdTime = now - btnWhitePressTime;
                btnWhiteHeld = false;
                if (holdTime < 1000) startLevelIntro(CONFIG_START_LEVEL);
            }
        }

        // --- STATE DISPATCHER (if/else-if replaces return-based dispatch) ---
        if (currentState == STATE_LEVEL_COMPLETED) {
            updateLevelCompletedAnim();
        }
        else if (currentState == STATE_BASE_DESTROYED) {
            updateBaseDestroyedAnim();
        }
        else if (currentState == STATE_GAME_FINISHED) {
            for (int i = 0; i < CONFIG_NUM_LEDS; i++)
                leds[i + ledStartOffset] = CHSV((now / 10) + (i * 5), 255, 255);
            if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
        }
        else if (currentState == STATE_GAMEOVER) {
            for (int i = 0; i < CONFIG_NUM_LEDS; i++) leds[i + ledStartOffset] = CRGB::Red;
            if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
        }
        else if (currentState == STATE_INTRO) {
            updateLevelIntro();
        }
        else if (currentState == STATE_BONUS_INTRO) {
            updateBonusIntro();
        }
        else if (currentState == STATE_BONUS_PLAYING) {
            updateBonusGame();
        }
        else if (currentState == STATE_BONUS_SIMON) {
            updateSimonBonus();
        }
        else if (currentState == STATE_PLAYING || currentState == STATE_BOSS_PLAYING) {
            // ---------------------------------------------------------------
            // MAIN GAME LOGIC — button reads changed to g_buttons
            // ---------------------------------------------------------------
            bool b = g_buttons.blue;
            bool r = g_buttons.red;
            bool g = g_buttons.green;
            bool isAnyBtnPressed = (b || r || g);

            if (!isAnyBtnPressed) { buttonsReleased = true; isWaitingForCombo = false; }

            if (currentBossType == 3 || currentLevel > 10) {
                if (isAnyBtnPressed && buttonsReleased && !isWaitingForCombo && (now - lastFireTime > FIRE_COOLDOWN)) {
                    isWaitingForCombo = true;
                    comboTimer        = now;
                }
                if (isWaitingForCombo && (now - comboTimer >= INPUT_BUFFER_MS)) {
                    // Combo re-read: g_buttons is continuously updated by digital input task
                    b = g_buttons.blue;
                    r = g_buttons.red;
                    g = g_buttons.green;
                    int c = 0;
                    if      (r && g && b) c = 7;
                    else if (r && g)      c = 4;
                    else if (r && b)      c = 5;
                    else if (g && b)      c = 6;
                    else if (b)           c = 1;
                    else if (r)           c = 2;
                    else if (g)           c = 3;
                    if (c > 0) { shots.push_back({0.0, c}); queueBuzzerEvent(BUZZER_EVENT_SHOT); lastFireTime = now; pushEvent(EVT_COMBO_TRIGGERED, c); } // AFTER UPDATE
                    buttonsReleased   = false;
                    isWaitingForCombo = false;
                }
            } else {
                if (isAnyBtnPressed && buttonsReleased && (now - lastFireTime > FIRE_COOLDOWN)) {
                    int c = 0;
                    if (b) c = 1; else if (r) c = 2; else if (g) c = 3;
                    if (c > 0) { shots.push_back({0.0, c}); queueBuzzerEvent(BUZZER_EVENT_SHOT); lastFireTime = now; }
                    buttonsReleased = false;
                }
            }

            // SHOT MOVEMENT + HIT DETECTION (unchanged logic)
            float moveStep = ((float)CONFIG_SHOT_SPEED_PCT / 60.0) * 0.6;
            if (moveStep < 0.2) moveStep = 0.2;

            for (int i = shots.size() - 1; i >= 0; i--) {
                shots[i].position += moveStep;
                bool remove = false;

                if (currentState == STATE_PLAYING) {
                    if (shots[i].position >= enemyFrontIndex && !enemies.empty()) {
                        if (shots[i].color == enemies[0].color) {
                            enemies.erase(enemies.begin());
                            enemyFrontIndex += 1.0;
                            flashPixel((int)shots[i].position);
                            remove = true;
                            pushEvent(EVT_ENEMY_DESTROYED, enemies.size()); // AFTER UPDATE
                            checkWinCondition();
                        } else {
                            enemies.insert(enemies.begin(), {shots[i].color, 0.0, false});
                            enemyFrontIndex -= 1.0;
                            remove = true;
                            pushEvent(EVT_COMBO_FAILED, shots[i].color); // AFTER UPDATE
                        }
                    }
                } else if (currentState == STATE_BOSS_PLAYING) {
                    for (int p = 0; p < (int)bossProjectiles.size(); p++) {
                        if (shots[i].position >= bossProjectiles[p].pos) {
                            if (shots[i].color == bossProjectiles[p].color) {
                                bossProjectiles.erase(bossProjectiles.begin() + p);
                                flashPixel((int)shots[i].position);
                            }
                            remove = true;
                            break;
                        }
                    }

                    if (!remove && shots[i].position >= enemyFrontIndex - 0.5 && !bossSegments.empty()) {
                        int hitIndex = (int)round(shots[i].position - enemyFrontIndex);
                        if (hitIndex >= (int)bossSegments.size()) hitIndex = bossSegments.size() - 1;
                        if (hitIndex < 0) hitIndex = 0;

                        bool vulnerable = false;
                        if      (currentBossType == 1) vulnerable = true;
                        else if (currentBossType == 2) { if (boss2State == B2_MOVE && bossSegments[hitIndex].active) vulnerable = true; }
                        else if (currentBossType == 3) { if (boss3State != B3_PHASE_CHANGE) vulnerable = true; }

                        if (vulnerable) {
                            if (shots[i].color == bossSegments[hitIndex].color) {
                                flashPixel((int)shots[i].position);
                                bossSegments[hitIndex].hp--;
                                if (bossSegments[hitIndex].hp <= 0) {
                                    bossSegments.erase(bossSegments.begin() + hitIndex);
                                    if (hitIndex == 0) enemyFrontIndex += 1.0;
                                    pushEvent(EVT_BOSS_SEGMENT_DESTROYED, hitIndex, (int)bossSegments.size()); // AFTER UPDATE
                                }
                                checkWinCondition();
                            } else {
                                if (currentBossType == 1) {
                                    currentScore = (currentScore > 50) ? currentScore - 50 : 0;
                                    if (!boss1RageMode) {
                                        boss1WrongHits++;
                                        if (boss1WrongHits >= 3) {
                                            boss1RageMode  = true;
                                            boss1RageShots = 5;
                                            bossActionTimer = now;
                                        }
                                    }
                                }
                            }
                        }
                        remove = true;
                    }
                }

                if (shots[i].position >= CONFIG_NUM_LEDS) remove = true;
                if (remove) shots.erase(shots.begin() + i);
            }

            // ENEMY / BOSS MOVEMENT (unchanged logic)
            if (currentState == STATE_PLAYING) {
                int mapLevel  = (currentLevel > 10) ? ((currentLevel - 1) % 10) + 1 : currentLevel;
                float eStep   = ((float)levels[mapLevel].speed / 60.0) * enemySpeedMultiplier;
                enemyFrontIndex -= eStep;
                if (enemyFrontIndex <= CONFIG_HOMEBASE_SIZE) triggerBaseDestruction();
            }
            else if (currentState == STATE_BOSS_PLAYING) {
                int pSpeed = 60;
                if      (currentBossType == 1) pSpeed = boss1Cfg.shotSpeed;
                else if (currentBossType == 2) pSpeed = boss2Cfg.shotSpeed;
                moveBossProjectiles((float)pSpeed);

                // BOSS 1: THE TANK
                if (currentBossType == 1) {
                    enemyFrontIndex -= ((float)boss1Cfg.moveSpeed / 60.0) * enemySpeedMultiplier;
                    if (enemyFrontIndex <= CONFIG_HOMEBASE_SIZE) triggerBaseDestruction();

                    if (boss1RageMode) {
                        if (now - bossActionTimer > 200) {
                            bossActionTimer = now;
                            int frontColor  = bossSegments.empty() ? 1 : bossSegments[0].color;
                            int rageColor;
                            do { rageColor = random(1, 4); } while (rageColor == frontColor);
                            bossProjectiles.push_back({enemyFrontIndex, rageColor});
                            boss1RageShots--;
                            if (boss1RageShots <= 0) { boss1RageMode = false; boss1WrongHits = 0; }
                        }
                    } else {
                        if (now - bossActionTimer > (boss1Cfg.shotFreq * 100)) {
                            bossActionTimer  = now;
                            int frontColor   = bossSegments.empty() ? 0 : bossSegments[0].color;
                            int shotColor;
                            if (random(100) < 20 && frontColor > 0) {
                                shotColor = frontColor;
                            } else {
                                do { shotColor = random(1, 4); } while (shotColor == frontColor && frontColor > 0);
                            }
                            bossProjectiles.push_back({enemyFrontIndex, shotColor});
                        }
                    }
                }
                // BOSS 2: MASTERBLASTER
                else if (currentBossType == 2) {
                    if (boss2State == B2_MOVE) {
                        enemyFrontIndex -= ((float)boss2Cfg.moveSpeed / 60.0) * enemySpeedMultiplier;
                        if (boss2Section < 3 && enemyFrontIndex <= markerPos[boss2Section]) {
                            boss2State      = B2_CHARGE;
                            bossActionTimer = now;
                            int survivors   = 0;
                            int startRange  = (boss2Section == 0) ? 0 : (boss2Section == 1) ? 3 : 6;
                            for (auto &seg : bossSegments) if (seg.originalIndex < startRange) survivors++;
                            boss2TargetShots = 10 + (survivors * 3);
                        }
                        if (enemyFrontIndex <= CONFIG_HOMEBASE_SIZE) triggerBaseDestruction();
                    } else if (boss2State == B2_CHARGE) {
                        if (now - bossActionTimer < (boss2Cfg.shotFreq * 100)) {
                            if (now % 100 < 20) boss2LockedColor = random(1, 4);
                        } else {
                            boss2State       = B2_SHOOT;
                            boss2ShotsFired  = 0;
                            bossActionTimer  = now;
                            int startRange   = (boss2Section == 0) ? 0 : 0;
                            int endRange     = (boss2Section == 0) ? 2 : (boss2Section == 1) ? 5 : 8;
                            for (auto &seg : bossSegments)
                                if (seg.originalIndex >= startRange && seg.originalIndex <= endRange)
                                    seg.color = boss2LockedColor;
                        }
                    } else if (boss2State == B2_SHOOT) {
                        if (now - bossActionTimer > 150) {
                            bossActionTimer = now;
                            bossProjectiles.push_back({enemyFrontIndex, boss2LockedColor});
                            boss2ShotsFired++;
                            if (boss2ShotsFired >= boss2TargetShots) {
                                int startRange = (boss2Section == 0) ? 0 : (boss2Section == 1) ? 3 : 0;
                                int endRange   = (boss2Section == 0) ? 2 : (boss2Section == 1) ? 5 : 8;
                                for (auto &seg : bossSegments)
                                    if (seg.originalIndex >= startRange && seg.originalIndex <= endRange)
                                        seg.active = true;
                                boss2State = B2_MOVE;
                                boss2Section++;
                            }
                        }
                    }
                }
                // BOSS 3: RGB OVERLORD
                else if (currentBossType == 3) {
                    float safeFireLimit = (CONFIG_NUM_LEDS > 180) ? 70.0 : (float)(CONFIG_HOMEBASE_SIZE + 5);

                    if (boss3State == B3_MOVE && boss3PhaseIndex < 2 && enemyFrontIndex <= boss3Markers[boss3PhaseIndex]) {
                        boss3State      = B3_PHASE_CHANGE;
                        bossActionTimer = now;
                    }

                    if (boss3State == B3_MOVE) {
                        enemyFrontIndex -= ((float)boss3Cfg.moveSpeed / 60.0) * enemySpeedMultiplier;
                        if (enemyFrontIndex <= CONFIG_HOMEBASE_SIZE) triggerBaseDestruction();
                        if (enemyFrontIndex > safeFireLimit && boss3Cfg.shotFreq > 0 &&
                            (now - bossActionTimer > (boss3Cfg.shotFreq * 100))) {
                            bossActionTimer = now;
                            bossProjectiles.push_back({enemyFrontIndex, (int)random(1, 4)});
                        }
                    } else if (boss3State == B3_PHASE_CHANGE) {
                        if (now - bossActionTimer > 4000) {
                            boss3State       = B3_BURST;
                            boss3BurstCounter = 0;
                            bossActionTimer  = now;
                            for (auto &seg : bossSegments) seg.color = random(4, 8);
                            boss3PhaseIndex++;
                        }
                    } else if (boss3State == B3_BURST) {
                        if (now - bossActionTimer > 200) {
                            bossActionTimer = now;
                            if (enemyFrontIndex > safeFireLimit)
                                bossProjectiles.push_back({enemyFrontIndex, (int)random(1, 8)});
                            boss3BurstCounter++;
                            if (boss3BurstCounter >= boss3Cfg.burstCount) {
                                boss3State      = B3_WAIT;
                                bossActionTimer = now;
                            }
                        }
                    } else if (boss3State == B3_WAIT) {
                        if (now - bossActionTimer > 2000) {
                            boss3State      = B3_MOVE;
                            bossActionTimer = now;
                        }
                    }
                }
            }

            // DRAW FRAME (unchanged rendering logic)
            FastLED.clear();

            if (currentState == STATE_BOSS_PLAYING) {
                if (currentBossType == 2) {
                    for (int i = 0; i < 3; i++)
                        if (markerPos[i] < enemyFrontIndex)
                            leds[markerPos[i] + ledStartOffset] = CRGB(50, 0, 0);
                } else if (currentBossType == 3) {
                    if (boss3PhaseIndex <= 0) { leds[boss3Markers[0] + ledStartOffset] = CRGB(50,0,0); leds[boss3Markers[0] + ledStartOffset + 1] = CRGB(50,0,0); }
                    if (boss3PhaseIndex <= 1) { leds[boss3Markers[1] + ledStartOffset] = CRGB(50,0,0); leds[boss3Markers[1] + ledStartOffset + 1] = CRGB(50,0,0); }
                }
            }

            if (currentState == STATE_PLAYING) {
                for (int i = 0; i < (int)enemies.size(); i++)
                    drawCrispPixel(enemyFrontIndex + (float)i, getColor(enemies[i].color));
            } else if (currentState == STATE_BOSS_PLAYING) {
                for (int i = 0; i < (int)bossSegments.size(); i++) {
                    float pos = enemyFrontIndex + (float)i;
                    if (pos < 0 || pos >= CONFIG_NUM_LEDS) continue;
                    CRGB c = getColor(bossSegments[i].color);

                    if (currentBossType == 1 && boss1RageMode) {
                        if ((millis() / 50) % 2 == 0) c = CRGB::White;
                    } else if (currentBossType == 2) {
                        c = col_cb;
                        if (boss2State == B2_MOVE) {
                            if (bossSegments[i].active) {
                                c = getColor(bossSegments[i].color);
                                if ((millis() / 100) % 2 == 0) c = CRGB::Black;
                            }
                        } else {
                            int oid = bossSegments[i].originalIndex;
                            bool highlight = (boss2Section == 0) ? (oid <= 2) : (boss2Section == 1) ? (oid <= 5) : true;
                            if (highlight) c = getColor(boss2LockedColor);
                        }
                    } else if (currentBossType == 3 && boss3State == B3_PHASE_CHANGE) {
                        c = CRGB::White;
                    }
                    drawCrispPixel(pos, c);
                }
                for (auto &p : bossProjectiles) drawCrispPixel(p.pos, getColor(p.color));
            }

            for (auto &s : shots) drawCrispPixel(s.position, getColor(s.color));
            for (int i = 0; i < CONFIG_HOMEBASE_SIZE; i++) leds[i + ledStartOffset] = CRGB::White;
            if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
            // FastLED.show() removed — output task handles it
        }

        // --- Update telemetry LED mirror before output renders the frame --- // AFTER UPDATE
        updateTelemetryLedMirror(); // AFTER UPDATE

        // --- Signal output task to render the LED frame ---
        xSemaphoreGive(xRenderSem);

        // --- Update snapshot for OLED and logging tasks ---
        takeGameSnapshot();

        // --- Event detection & runtime assertions --- // AFTER UPDATE
        checkStateTransitionEvents(); // AFTER UPDATE
        runTelemetryAssertions(); // AFTER UPDATE

        // --- FPS measurement (microsecond precision) --- // AFTER UPDATE
        static unsigned long frameStartUs = 0; // AFTER UPDATE
        static unsigned long fpsCounterTime = 0; // AFTER UPDATE
        static unsigned long fpsFrames = 0; // AFTER UPDATE
        unsigned long nowUs = micros(); // AFTER UPDATE
        if (frameStartUs > 0) g_lastFrameTimeUs = nowUs - frameStartUs; // AFTER UPDATE
        frameStartUs = nowUs; // AFTER UPDATE
        fpsFrames++; // AFTER UPDATE
        if (millis() - fpsCounterTime >= 1000) { // AFTER UPDATE
            g_currentFPS = (float)fpsFrames; // AFTER UPDATE
            fpsFrames = 0; // AFTER UPDATE
            fpsCounterTime = millis(); // AFTER UPDATE
        } // AFTER UPDATE

        // --- Task heartbeat --- // AFTER UPDATE
        updateTaskHeartbeat(2); // AFTER UPDATE

        // --- Increment FPS counter ---
        g_frameCount++;

        // --- Maintain ~60 FPS period ---
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(FRAME_DELAY));
    }
}

// --- Task 4: Output / Actuator (LED rendering) ---
void vOutputTask(void *pvParameters) {
    for (;;) {
        updateTaskHeartbeat(3); // AFTER UPDATE
        // Block until game task signals a frame is ready
        xSemaphoreTake(xRenderSem, portMAX_DELAY);
        FastLED.show();
    }
}

// --- Task 5: Communication (OLED HUD via I2C) ---
void vOledCommTask(void *pvParameters) {
    for (;;) {
        updateTaskHeartbeat(4); // AFTER UPDATE
        if (!oledReady) {
            vTaskDelay(pdMS_TO_TICKS(1000));
            continue;
        }

        // Copy snapshot under mutex (microseconds hold time)
        GameSnapshot snap;
        xSemaphoreTake(xSnapshotMutex, portMAX_DELAY);
        snap = g_snapshot;
        xSemaphoreGive(xSnapshotMutex);

        // Render to OLED framebuffer then push over I2C
        renderOledFromSnapshot(snap);
        display.display();

        vTaskDelay(pdMS_TO_TICKS(OLED_REFRESH_MS));
    }
}

// --- Task 6: Logging / Diagnostic ---
void vLoggingTask(void *pvParameters) {
    unsigned long lastLogTime = 0;
    unsigned long lastFrameCount = 0;

    for (;;) {
        updateTaskHeartbeat(5); // AFTER UPDATE
        // Copy snapshot with timeout (demonstrates timeout-based mutex take)
        GameSnapshot snap;
        if (xSemaphoreTake(xSnapshotMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
            snap = g_snapshot;
            xSemaphoreGive(xSnapshotMutex);
        } else {
            // Mutex timeout — skip this log cycle
            vTaskDelay(pdMS_TO_TICKS(500));
            continue;
        }

        unsigned long now = millis();
        unsigned long elapsed = now - lastLogTime;
        unsigned long frames  = g_frameCount - lastFrameCount;
        float fps = (elapsed > 0) ? (frames * 1000.0 / elapsed) : 0.0;
        lastLogTime    = now;
        lastFrameCount = g_frameCount;

        xSemaphoreTake(xSerialMutex, portMAX_DELAY);
        Serial.printf("[LOG] State=%-12s Lv=%2d Score=%6d FPS=%.1f Heap=%d\n",
            getStateLabelFor(snap.state), snap.level, snap.score, fps,
            (int)esp_get_free_heap_size());
        xSemaphoreGive(xSerialMutex);

        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

// --- Task 7: Buzzer / Sound Effects ---
void vBuzzerTask(void *pvParameters) {
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_BUZZER, LOW);

    BuzzerEvent event;

    for (;;) {
        updateTaskHeartbeat(6); // AFTER UPDATE
        if (xQueueReceive(xBuzzerQueue, &event, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        if (event.type == BUZZER_EVENT_SHOT) {
            // Very short pulse for player bullet fire.
            digitalWrite(PIN_BUZZER, HIGH);
            vTaskDelay(pdMS_TO_TICKS(25));
            digitalWrite(PIN_BUZZER, LOW);
        }
        else if (event.type == BUZZER_EVENT_LEVEL_CLEAR) {
            // Celebration rhythm for level/boss completion.
            const uint16_t pattern[][2] = {
                {80,  50},
                {80,  50},
                {130, 70},
                {180, 90},
                {280, 0}
            };

            for (uint8_t i = 0; i < sizeof(pattern) / sizeof(pattern[0]); i++) {
                digitalWrite(PIN_BUZZER, HIGH);
                vTaskDelay(pdMS_TO_TICKS(pattern[i][0]));
                digitalWrite(PIN_BUZZER, LOW);

                if (pattern[i][1] > 0) {
                    vTaskDelay(pdMS_TO_TICKS(pattern[i][1]));
                }
            }
        }
    }
}


// --- Task 8: WiFi WebSocket Telemetry (Enhanced) --- // AFTER UPDATE
void vTelemetryTask(void *pvParameters) { // AFTER UPDATE
    telemetryJsonPacket.reserve(TELEMETRY_JSON_RESERVE_BYTES); // AFTER UPDATE
    TickType_t xLastTelemetryWakeTime = xTaskGetTickCount(); // AFTER UPDATE
    for (;;) { // AFTER UPDATE
        updateTaskHeartbeat(7); // AFTER UPDATE
        handleTelemetryWiFi(); // AFTER UPDATE
        if (telemetryWebSocketStarted && WiFi.status() == WL_CONNECTED) { // AFTER UPDATE
            webSocket.loop(); // AFTER UPDATE
            unsigned long now = millis(); // AFTER UPDATE

            // --- Drain event queue (instant send) --- // AFTER UPDATE
            TelemetryEvent evt; // AFTER UPDATE
            while (xQueueReceive(xEventQueue, &evt, 0) == pdPASS) { // AFTER UPDATE
                sendEventPacket(evt); // AFTER UPDATE
            } // AFTER UPDATE

            // --- Drain bug queue (instant send) --- // AFTER UPDATE
            BugReport bug; // AFTER UPDATE
            while (xQueueReceive(xBugQueue, &bug, 0) == pdPASS) { // AFTER UPDATE
                sendBugPacket(bug); // AFTER UPDATE
            } // AFTER UPDATE

            // --- Gameplay telemetry (100ms) --- // AFTER UPDATE
            if (now - telemetryTimer >= TELEMETRY_INTERVAL_MS) { // AFTER UPDATE
                telemetryTimer = now; // AFTER UPDATE
                sendTelemetry(); // AFTER UPDATE
            } // AFTER UPDATE

            // --- Diagnostics packet (500ms) --- // AFTER UPDATE
            if (now - telemetryDiagTimer >= TELEMETRY_DIAG_INTERVAL_MS) { // AFTER UPDATE
                telemetryDiagTimer = now; // AFTER UPDATE
                sendDiagnosticsPacket(); // AFTER UPDATE
            } // AFTER UPDATE

            // --- Serial debug print (3s) --- // AFTER UPDATE
            if (now - telemetryLastDebugPrint >= 3000) { // AFTER UPDATE
                telemetryLastDebugPrint = now; // AFTER UPDATE
                Serial.printf("[TEL] clients=%d packets=%lu fps=%.0f heap=%d rssi=%d\n", webSocket.connectedClients(), telemetryPacketsSent, g_currentFPS, (int)esp_get_free_heap_size(), WiFi.RSSI()); // AFTER UPDATE
            } // AFTER UPDATE
        } // AFTER UPDATE
        vTaskDelayUntil(&xLastTelemetryWakeTime, pdMS_TO_TICKS(5)); // AFTER UPDATE
    } // AFTER UPDATE
} // AFTER UPDATE

// --------------------------------------------------------------------------
// 20. SETUP
// --------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);
    setupWiFi(); // AFTER UPDATE
    initOLED();

    pinMode(PIN_BTN_BLUE,  INPUT_PULLUP);
    pinMode(PIN_BTN_RED,   INPUT_PULLUP);
    pinMode(PIN_BTN_GREEN, INPUT_PULLUP);
    pinMode(PIN_BTN_WHITE, INPUT_PULLUP);

    pinMode(POT_PIN, INPUT);
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_BUZZER, LOW);

    analogReadResolution(12);
    analogSetPinAttenuation(POT_PIN, ADC_11db);

    loadColors();
    setupDefaultConfig();

    FastLED.addLeds<LED_TYPE, PIN_LED_DATA, COLOR_ORDER>(leds, CONFIG_NUM_LEDS + 1);
    FastLED.setBrightness(map(CONFIG_BRIGHTNESS_PCT, 10, 100, 25, 255));
    FastLED.setDither(0);
    FastLED.setMaxPowerInVoltsAndMilliamps(5, 2500);

    if (CONFIG_SACRIFICE_LED) leds[0] = CRGB(20, 0, 0);
    FastLED.show();

    // Start at level intro (writes to leds[] but output task not running yet)
    startLevelIntro(CONFIG_START_LEVEL);
    FastLED.show();   // one-shot show before tasks take over

    // --- Create RTOS synchronisation objects ---
    xPotQueue      = xQueueCreate(5, sizeof(int));
    xBuzzerQueue   = xQueueCreate(10, sizeof(BuzzerEvent));
    xButtonISRSem  = xSemaphoreCreateBinary();
    xRenderSem     = xSemaphoreCreateBinary();
    xInputMutex    = xSemaphoreCreateMutex();
    xSnapshotMutex = xSemaphoreCreateMutex();
    xSerialMutex   = xSemaphoreCreateMutex();
    xTelemetryMutex = xSemaphoreCreateMutex(); // AFTER UPDATE
    xEventQueue = xQueueCreate(20, sizeof(TelemetryEvent)); // AFTER UPDATE
    xBugQueue = xQueueCreate(10, sizeof(BugReport)); // AFTER UPDATE

    // --- Init RTOS task heartbeat names --- // AFTER UPDATE
    g_taskHeartbeats[0] = {0, 0, "AnalogSensor"}; // AFTER UPDATE
    g_taskHeartbeats[1] = {0, 0, "DigitalInput"}; // AFTER UPDATE
    g_taskHeartbeats[2] = {0, 0, "GameProcess"}; // AFTER UPDATE
    g_taskHeartbeats[3] = {0, 0, "OutputLED"}; // AFTER UPDATE
    g_taskHeartbeats[4] = {0, 0, "OledComm"}; // AFTER UPDATE
    g_taskHeartbeats[5] = {0, 0, "Logging"}; // AFTER UPDATE
    g_taskHeartbeats[6] = {0, 0, "BuzzerSFX"}; // AFTER UPDATE
    g_taskHeartbeats[7] = {0, 0, "TelemetryWS"}; // AFTER UPDATE

    // --- Attach button interrupts (FALLING edge) ---
    attachInterrupt(digitalPinToInterrupt(PIN_BTN_BLUE),  onButtonISR, FALLING);
    attachInterrupt(digitalPinToInterrupt(PIN_BTN_RED),   onButtonISR, FALLING);
    attachInterrupt(digitalPinToInterrupt(PIN_BTN_GREEN), onButtonISR, FALLING);
    attachInterrupt(digitalPinToInterrupt(PIN_BTN_WHITE), onButtonISR, FALLING);

    // --- Launch 8 RTOS tasks --- // AFTER UPDATE
    xTaskCreatePinnedToCore(vAnalogSensorTask,  "AnalogSensor",  3072, NULL, 2, &hAnalogTask,  0); // AFTER UPDATE
    xTaskCreatePinnedToCore(vDigitalInputTask,   "DigitalInput",  4096, NULL, 3, &hDigitalTask, 1); // AFTER UPDATE
    xTaskCreatePinnedToCore(vGameProcessingTask, "GameProcess",   16384, NULL, 4, &hGameTask,    1); // AFTER UPDATE
    xTaskCreatePinnedToCore(vOutputTask,          "OutputLED",     4096, NULL, 5, &hOutputTask,  1); // AFTER UPDATE
    xTaskCreatePinnedToCore(vOledCommTask,        "OledComm",      6144, NULL, 2, &hOledTask,    0); // AFTER UPDATE
    xTaskCreatePinnedToCore(vLoggingTask,         "Logging",       4096, NULL, 1, &hLogTask,     0); // AFTER UPDATE
    xTaskCreatePinnedToCore(vBuzzerTask,          "BuzzerSFX",     3072, NULL, 3, &hBuzzerTask,  0); // AFTER UPDATE
    xTaskCreatePinnedToCore(vTelemetryTask,       "TelemetryWS",   12288, NULL, 1, &hTelemetryTask, 0); // AFTER UPDATE
}

// --------------------------------------------------------------------------
// 21. LOOP — empty, all work done in RTOS tasks
// --------------------------------------------------------------------------
void loop() {
    vTaskDelay(portMAX_DELAY);
}
