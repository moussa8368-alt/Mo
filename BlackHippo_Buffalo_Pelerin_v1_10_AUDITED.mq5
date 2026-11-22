//==================================================================
// BlackHippo Buffalo-Pelerin v1.10 — AUDIT STATIC PRE-DEPLOYMENT
// Source de référence conservée sans modification fonctionnelle.
// Audit statique effectué avant compilation MetaEditor.
// Ne pas considérer ce fichier comme « validé réel » avant compilation,
// Strategy Tester, forward test démo et tests d'exécution broker.
//==================================================================

//+------------------------------------------------------------------+
//| BlackHippo Buffalo-Pelerin                                       |
//|                                                                  |
//| Expert Advisor multi-symboles :                                  |
//| - Gestion du risque et de l'exposition portefeuille              |
//| - Analyse des corrélations et sélection des signaux               |
//| - Gestion des positions et des sorties                            |
//| - Surveillance, tableau de bord et journal diagnostic            |
//|                                                                  |
//| Compiler, tester et valider en compte démo avant toute utilisation|
//| en réel. Aucune garantie de performance.                         |
//+------------------------------------------------------------------+
#property copyright "CLY.MO"
#property version   "1.10"
#property description "BlackHippo Buffalo-Pelerin – risk controls, diagnostics, robust position management"

#include <Trade\Trade.mqh>

#define HALT_NONE      0
#define HALT_LOSS      1
#define HALT_TARGET    2
#define HALT_CRITICAL  3
#define HALT_WEEKLY    4

//======================== OPERATING PROFILE ========================
// Keep CUSTOM=1 for backward compatibility with existing .set files.
enum CLY_RISK_PROFILE {
   CLY_RISK_SAFE=0,
   CLY_RISK_BALANCED=2,
   CLY_RISK_DYNAMIC=3,
   CLY_RISK_CUSTOM=1
};

//======================== MULTI-PAGE DASHBOARD ========================
enum DASH_PAGE {
   PAGE_HOME = 0,
   PAGE_RISK,
   PAGE_SIGNAL,
   PAGE_MR,
   PAGE_EXITS,
   PAGE_FILTERS,
   PAGE_ADVANCED
};

DASH_PAGE g_dashPage  = PAGE_HOME;
bool      g_dashDirty = false;
int       g_dashBuiltPage = -1;

// Variables effectives (modifiables via le dashboard)
double g_effRiskPercent         = 0.20;
double g_effMaxRiskPerTrade     = 0.50;
double g_effMaxTotalRiskPct     = 1.25;
double g_effMaxCurrencyRiskPct  = 0.75;
int    g_effMaxOpenTrades       = 3;
int    g_effMaxSameDirection    = 2;
int    g_effMaxTradesPerDay     = 6;
double g_effMaxDailyLossPct     = 2.00;
double g_effMaxWeeklyLossPct    = 4.00;

struct DashDraft {
   double riskPercent;
   double maxRiskPerTrade;
   double maxTotalRiskPct;
   double maxCurrencyRiskPct;
   int    maxOpenTrades;
   int    maxSameDirection;
   int    maxTradesPerDay;
   double maxDailyLossPct;
   double maxWeeklyLossPct;
};
DashDraft g_draft;

input CLY_RISK_PROFILE InpRiskProfile = CLY_RISK_BALANCED; // profil initial équilibré si aucun profil mémorisé
input bool InpRememberRiskProfile = true; // mémoriser le profil choisi sur ce compte/serveur/Magic
input bool InpForceInputProfile = false; // true : ignore le profil mémorisé et applique InpRiskProfile au démarrage
input bool InpHaltRequiresManualRearm = false; // live : true = toute halte (perte, objectif) désarme les entrées jusqu'à un nouveau clic ARMER (halte critique : toujours manuel)
input bool InpRequireManualArm = true; // aucune nouvelle entrée avant clic explicite sur ARMER
input bool InpEnableConfigBridge = true; // export JSON en lecture seule dans le dossier commun MT5
input bool InpAutoScanMarketWatch = false; // désactivé par défaut : évite de trader automatiquement tous les Forex du Market Watch
input int InpMaxAutoSymbols = 20;          // plafond de charge et d'exposition
input group "=== Surveillance ==="
input bool InpEnableHealthMonitor = true; // journal de santé du robot (sans action de trading)
input int  InpHealthIntervalSec = 60;     // fréquence du rapport de santé
input int  InpHealthMaxQuoteAgeSec = 180; // seuil d'alerte sur cotation trop ancienne
input bool InpEnableDiagnosticLog = true;  // journal d'événements CSV (dossier Common)
input string InpDiagnosticFile = "CLY_MO_Diagnostic.csv";
input bool InpShowDashboard = true;       // tableau de bord graphique en lecture seule
input int  InpDashboardX = 12;             // position horizontale (pixels)
input int  InpDashboardY = 18;             // position verticale (pixels)


//======================== INPUTS ========================
input group "=== Général ==="
input long             InpMagic              = 20260105;
input string           InpSymbols            = "EURUSD,GBPUSD,USDJPY,AUDUSD,EURGBP,AUDNZD";
input string           InpSymbolSuffix       = "";        // suffixe broker (ex: .a, m)
input bool             InpTradeOnlyCurrent   = true;        // démarrage novice : ne traite que le symbole du graphique
input ENUM_TIMEFRAMES  InpEntryTF            = PERIOD_M5;
input ENUM_TIMEFRAMES  InpConfirmTF          = PERIOD_M15;
input ENUM_TIMEFRAMES  InpHigherTF           = PERIOD_H1;

input group "=== Risque ==="
input double InpRiskPercent         = 0.20;   // % equity risqué par trade (avant multiplicateurs)
input double InpMaxRiskPerTrade     = 0.50;   // plafond dur % equity par trade
input double InpMaxTotalRiskPct     = 1.25;   // risque cumulé au SL, % equity
input double InpMaxCurrencyRiskPct  = 0.75;   // risque brut par devise, % equity (sans compensation)
input bool   InpPortfolioAllPositions = true; // inclure positions manuelles/autres EA dans les plafonds portefeuille
input int    InpMaxOpenTrades       = 3;
input int    InpMaxSameDirection    = 2;
input int    InpMaxTradesPerDay     = 6;
input int    InpMaxTradesPerSymbol  = 2;      // par jour
input double InpMaxDailyLossPct     = 2.00;   // perte jour (réalisée + flottante) vs equity de début de jour
input double InpDailyProfitTargetPct= 0.0;    // 0 = désactivé (stoppe les entrées)
input double InpMaxWeeklyLossPct    = 4.00;   // perte semaine (réalisée + flottante) vs equity du lundi, 0 = désactivé
input bool   InpCloseOnHalt         = true;   // ferme les positions de cet EA (Magic), pas les trades manuels/autres EA
input int    InpMaxConsecLosses     = 3;
input int    InpPauseMinutes        = 60;
input double InpMaxMarginUsePct     = 30.0;
input double InpCommissionPerLot    = 7.0;    // aller-retour par lot, devise du compte (0 = aucun)

input group "=== Réduction de risque adaptative ==="
input bool   InpUseDDScaling        = true;   // selon le drawdown depuis le plus haut d'equity
input double InpDDStartPct          = 1.0;
input double InpDDFullPct           = 5.0;
input double InpDDFloorMult         = 0.25;
input bool   InpResetPeakOnInit     = false;
input bool   InpResetCriticalHalt   = false;  // lève une halte critique persistante au démarrage
input bool   InpUseRollingPF        = true;   // selon le profit factor glissant
input int    InpRollTrades          = 20;
input double InpPFLow               = 0.85;
input double InpPFGood              = 1.35;
input double InpPFLowMult           = 0.50;
input double InpPFGoodMult          = 1.10;

input group "=== Signal ==="
input int    InpEMAFast             = 8;
input int    InpEMASlow             = 21;
input int    InpEMATrend            = 50;
input int    InpEMAConfirm          = 21;     // EMA sur InpConfirmTF
input int    InpEMAH1               = 34;     // EMA sur InpHigherTF
input int    InpRSIPeriod           = 8;
input double InpRSIPullBuy          = 42.0;   // creux RSI récent <= ce niveau (achat)
input double InpRSIPullSell         = 58.0;   // sommet RSI récent >= ce niveau (vente)
input int    InpADXPeriod           = 14;
input double InpADXMin              = 20.0;
input double InpADXStrong           = 30.0;
input double InpMinADXRise          = -100.0; // ADX[1] - ADX[3] minimal (-100 = filtre désactivé, 0 = ADX non décroissant)
input int    InpATRPeriod           = 14;
input int    InpATRRefPeriod        = 50;
input double InpMinEMASepATR        = 0.10;   // (EMA rapide - lente) >= x * ATR
input int    InpERLookback          = 12;     // efficacité directionnelle
input double InpMinER               = 0.25;
input double InpStrongER            = 0.40;
input double InpMaxATRRatio         = 2.00;   // ATR / ATR réf. maximal
input double InpHighVolRatio        = 1.60;   // au-dessus : risque réduit
input double InpHighVolRiskCut      = 0.50;
input double InpMaxSignalCandleATR  = 1.60;
input double InpMinBodyRatio        = 0.30;
input double InpMaxExtensionATR     = 1.20;   // |close - EMA rapide| <= x * ATR
input double InpRiskMultStrong      = 1.00;
input double InpRiskMultNormal      = 0.75;

input group "=== Filtres de signal (ablation : désactiver un à un) ==="
input bool   InpUseATRRatioFilter   = true;   // ATR / ATR réf. <= MaxATRRatio
input bool   InpUseADXFilter        = true;   // ADX >= ADXMin (et ADX-rise)
input bool   InpUseERFilter         = true;   // efficacité directionnelle >= MinER
input bool   InpUseCandleFilter     = true;   // taille + corps de la bougie signal
input bool   InpUseExtensionFilter  = true;   // |close - EMA rapide| <= x ATR
input bool   InpUseEMASepFilter     = true;   // séparation EMA rapide/lente >= x ATR
input bool   InpUseConfirmTFFilter  = true;   // biais InpConfirmTF
input bool   InpUseHigherTFFilter   = true;   // biais InpHigherTF
input bool   InpUseRSIPullback      = true;   // creux/sommet RSI + rebond

input group "=== Moteur de signal adaptatif ==="
input bool   InpUseAdaptiveScoring  = true;   // score adaptatif (sinon seuil fixe InpScoreBaseThreshold)
input double InpScoreBaseThreshold  = 72.0;   // seuil sélectif (à calibrer en walk-forward)
input double InpScoreStrongDiscount = 5.0;    // seuil abaissé si tendance forte et volatilité saine
input double InpScoreChopPenalty    = 10.0;   // pénalité accrue en marché faible / haché
input int    InpScoreVolumeLookback = 20;     // moyenne tick volume (barres clôturées)
input int    InpScoreStructureBars  = 6;      // fenêtre BOS / structure courte
input bool   InpUsePullbackSetup    = true;   // setup 1 : continuation après repli (RSI + reprise EMA)
input bool   InpUseBreakoutSetup    = true;   // setup 2 : continuation par cassure de structure
input double InpMinSetupPoints      = 16.0;   // points minimaux du meilleur trigger (sur 30)
input bool   InpHardRegimeGate      = true;   // garde-fous durs (plancher ADX/ER, veto H1 contraire)
input double InpHardADXFloorFrac    = 0.75;   // ADX >= ADXMin * frac, sinon rejet
input double InpHardERFloorFrac     = 0.60;   // ER  >= MinER  * frac, sinon rejet
input bool   InpLogSignalScore      = true;   // score, seuil, setup dans le journal / CSV
input double InpHardATRRatioMult   = 1.25;   // rejet dur si ATR/ATR réf. > MaxATRRatio × ce facteur
input double InpHardCandleMult     = 1.50;   // rejet dur si bougie signal > MaxSignalCandleATR × facteur × ATR
input double InpHardExtensionMult  = 1.50;   // rejet dur si |close - EMA rapide| > MaxExtensionATR × facteur × ATR

input group "=== Mean Reversion ==="
input bool   InpUseMeanReversion   = true;   // moteur range indépendant
input int    InpMRBandsPeriod      = 20;     // Bollinger calculées sur clôtures terminées
input double InpMRBandsDeviation  = 2.0;
input double InpMRRSIBuy           = 32.0;   // RSI <= seuil pour achat en excès baissier
input double InpMRRSISell          = 68.0;   // RSI >= seuil pour vente en excès haussier
input double InpMRADXMax           = 18.0;   // mean reversion autorisée seulement si ADX <= plafond
input double InpMRERMax            = 0.30;   // et efficacité directionnelle faible
input double InpMRRiskMult         = 0.50;   // risque réduit pour les retours à la moyenne
input double InpMRMinBandWidthATR  = 0.80;   // évite les bandes trop comprimées

input group "=== Mean Reversion : sorties dédiées ==="
input double InpMRScoreThreshold   = 68.0;   // score continu (0-100), à calibrer en walk-forward
input double InpMRMinRR            = 0.95;   // distance minimale vers la médiane / distance SL
input double InpMRH1FlatATR        = 1.60;   // |pente EMA H1 sur 3 barres| <= x * ATR M5 (0 = désactivé)
input int    InpMRMaxHoldBars      = 7;      // time-stop court (barres InpEntryTF)
input double InpMRBETriggerR       = 0.60;   // break-even précoce (0 = désactivé)
input double InpMRMaxCostToTP      = 0.15;   // coût/TP maximal pour la mean reversion
input bool   InpMRUseOppositeBand  = false;  // TP = bande opposée (plus ambitieux) sinon médiane
input double InpMRVolSpikeMult     = 1.35;   // tick volume de la bougie signal >= mult * moyenne

input group "=== Régimes & Vol Targeting ==="
input bool   InpUseRegimeEngine    = true;   // détection TREND / RANGE / HIGH_VOL / TRANSITION
input double InpHighVolATRRatio    = 1.80;   // au-delà = régime HIGH_VOL (risque réduit)
input double InpTrendADXFloor      = 22.0;   // ADX minimum pour considérer TREND
input double InpRangeADXCeil       = 18.0;   // ADX maximum pour considérer RANGE
input double InpRegimeRiskTrend    = 1.00;
input double InpRegimeRiskRange    = 0.55;
input double InpRegimeRiskHighVol  = 0.35;
input double InpRegimeRiskTrans    = 0.45;
input bool   InpUseVolTargeting    = true;   // cible un risque journalier constant
input double InpDailyRiskBudgetPct = 1.20;   // % equity de risque journalier cible (réalisé+flottant)
input double InpVolTargetFloor     = 0.40;   // plancher du multiplicateur vol-targeting
input double InpVolTargetCeil      = 1.25;   // plafond

input group "=== Sélection / Cooldown / News / Risque ==="
input int    InpMaxBadFills        = 3;      // fills rejetés par jour avant pause (0 = off)
input int    InpRankWaitSec        = 2;      // attente avant exécution pour classer les signaux simultanés
input int    InpCooldownExitBars   = 2;      // pause après toute sortie sur le symbole (barres)
input int    InpCooldownLossBars   = 6;      // pause après une sortie perdante (barres)
input int    InpNewsExitMin        = 4;      // ferme les positions N min avant un événement à fort impact (0 = off)
input double InpRiskMultFloor      = 0.00;   // aucun plancher forcé : DD/PF/régime peuvent réduire le risque jusqu’à zéro
input int    InpPFMinTrades        = 15;     // trades minimum avant d'appliquer le multiplicateur PF
input double InpScratchFrac        = 0.12;   // |net| <= frac * risque : scratch (hors série de pertes)
input bool   InpLogSignals         = true;   // CSV de toutes les évaluations de signal
input string InpSignalsFile        = "CLY_MO_Signals.csv";
input double InpMinScoreMargin     = 4.0;    // score - seuil minimal pour être candidat (plus sélectif)
input double InpSpreadPctileMax    = 0.70;   // spread courant <= percentile historique (0=off)
input double InpMaxCorrelation     = 0.75;   // rejeter si corrélation |r| trop élevée avec une position ouverte même direction (0=off)
input group "=== Confirmation finale des entrées ==="
input bool   InpRevalidateCandidate = true;  // recalculer le signal juste avant l'ordre
input double InpMaxEntryDistanceATR = 0.30;  // seuil de base anti-poursuite (ATR) strict
input bool   InpUseAdaptiveAntiChase = true; // tolérance dynamique selon qualité/force du signal
input double InpAdaptiveMaxDistanceATR = 0.55; // plafond absolu adaptatif (ATR)
input double InpAdaptiveMinADX = 28.0; // ADX requis pour assouplir le filtre
input double InpAdaptiveMinER = 0.38; // ER requis pour assouplir le filtre
input double InpAdaptiveMinScoreMargin = 7.0; // marge score-seuil requise pour assouplir
input double InpChaseRiskReduction = 0.70; // réduction maximale du risque sur extension (0..1)
input bool   InpUsePullbackRecovery = true; // conserver un signal étendu pour une reprise après repli
input double InpPullbackWatchMaxATR = 0.90; // distance maximale initiale surveillée (ATR)
input double InpPullbackMinRetraceATR = 0.12; // repli minimal depuis l extrême avant reprise
input double InpMaxCandidateATRChange = 0.20;// refuser si ATR change trop entre signal et exécution

input group "=== SL / TP / Coûts ==="
input int    InpStructBars          = 12;
input double InpStructBufATR        = 0.30;
input double InpMinStructATR        = 0.90;
input double InpMaxStructATR        = 2.40;   // au-delà : trade refusé (pas de SL tronqué)
input double InpRRBase              = 1.40;
input double InpRRStrong            = 1.70;
input double InpMaxCostToTP         = 0.10;   // (spread+commission) / distance TP
input double InpMaxSpreadPoints     = 25;
input double InpMaxSpreadATRFrac    = 0.15;
input int    InpExtraStopBufPts     = 2;

input group "=== Sorties ==="
input bool   InpUsePartial          = true;
input double InpPartialR            = 1.00;
input double InpPartialPct          = 50.0;
input bool   InpUseBE               = true;
input double InpBETriggerR       = 1.00;
input double InpBEOffsetPoints      = 2;      // + spread courant
input bool   InpUseTrail            = true;
input double InpTrailStartR         = 1.00;
input double InpTrailATR            = 1.10;
input double InpTrailStrongMult     = 1.25;   // si ADX fort
input bool   InpUseProfitLock       = true;   // verrouille une fraction du R initial après progression
input double InpProfitLockTriggerR  = 1.50;   // activation du verrouillage des gains
input double InpProfitLockR         = 0.25;   // SL sécurisant +0.25R (hors frais et slippage)
input bool   InpUseTimeStop         = true;
input int    InpMaxHoldBars         = 18;     // barres InpEntryTF
input double InpTimeStopMinR        = 0.35;   // ferme si R < ce seuil après la durée max

input group "=== Horaires (heure SERVEUR) ==="
input int    InpStartHour           = 8;
input int    InpEndHour             = 17;     // dernière entrée
input int    InpFridayEndHour       = 15;
input int    InpSkipOpenMin         = 10;     // minutes ignorées après StartHour
input int    InpCloseHour           = 19;
input int    InpCloseMinute         = 45;
input int    InpFridayCloseHour     = 18;
input int    InpFridayCloseMinute   = 40;

input group "=== News ==="
input bool   InpUseNewsWindows      = false;  // fenêtres statiques : à régler selon TON broker (heure serveur)
input string InpNewsWindows         = "12:25-13:20,14:25-15:20"; // HH:MM-HH:MM, heure serveur
input string InpNewsDays            = "1,2,3,4,5"; // jours de semaine concernés (0=dim..6=sam), ex: "3,5"
input int    InpNewsBufferMin       = 5;
input bool   InpUseCalendarFile     = false;  // CSV: "YYYY.MM.DD HH:MM,CUR,IMPACT" (heure serveur)
input string InpCalendarFile        = "CLY_MO_News.csv";
input bool   InpUseNativeCalendar   = true;  // recommandé: calendrier intégré MT5 (heure serveur)
input bool   InpUseCalendarWebRequest = false; // télécharger le CSV depuis une URL HTTPS
input string InpCalendarURL         = "";       // URL directe vers un CSV brut, sans page HTML
input int    InpCalendarRefreshSec  = 600;      // fréquence de téléchargement (10 min)
input int    InpCalendarTimeoutMs   = 5000;     // WebRequest est synchrone
input bool   InpCalendarCommon      = false;  // fichier dans le dossier Common
input bool   InpFailClosedCalendar  = true;
input bool   InpTesterFailClosedCalendar = false; // sans CSV historique valide, ne bloque pas le backtest par défaut
input bool   InpRequireFreshCal     = true;
input int    InpCalendarMaxAgeH     = 36;
input int    InpCalMinImpact        = 3;
input int    InpCalMinBefore        = 20;
input int    InpCalMinAfter         = 15;

input group "=== Exécution ==="
input int    InpMaxRetries          = 3;
input int    InpRetryDelayMs        = 150;
input int    InpBaseDeviation       = 10;
input double InpDevATRMult          = 0.20;   // points de déviation = base + ATR(points) * mult
input int    InpMaxDeviation        = 40;
input double InpMaxFillDevATR       = 0.30;
input double InpPostFillRiskTolPct  = 10.0;
input int    InpMaxQuoteAgeSec      = 30;
input int    InpUncertainLockMin    = 20;
input int    InpEntryWindowSec      = 90;     // fenêtre d'entrée après l'ouverture de la barre
input int    InpCooldownBars        = 3;

input group "=== Logs ==="
input bool   InpVerbose             = true;
input bool   InpCSV                 = true;
input string InpCSVFile             = "CLY_MO_Trades.csv";

input group "=== Optimisation (OnTester) ==="
input int    InpTesterMinTrades     = 120;    // échantillon minimal
input double InpTesterMaxDDPct      = 22.0;   // DD relatif maximal

//======================== STRUCTURES ========================
struct SymState {
   string   name;
   int      hEmaF, hEmaS, hEmaT, hRsi, hAdx, hAtr, hAtrRef, hH1, hM15;
   datetime lastBar;
   datetime lastEntryBar;
   datetime lockUntil;
   datetime lastExit;
   bool     lastExitLoss;
   datetime rejBar;
   bool     done;
   int      tradesToday;
   int      digits;
   double   point;
   string   base, quote;
};

struct NewsEvt { datetime t; string ccy; int impact; bool allDay; };

//======================== GLOBALS ========================
CTrade    g_trade;
CLY_RISK_PROFILE g_activeRiskProfile = CLY_RISK_SAFE; // profil actif, mémorisable
bool      g_entriesArmed = false; // fail-safe : désarmé au démarrage live par défaut
SymState  g_s[];
int       g_n = 0;
datetime  g_lastHealthReport = 0;
int       g_lastHealthFlags = -1;
datetime  g_lastConfigExport = 0;


datetime  g_day = 0;
double    g_dayEquity = 0, g_peak = 0;
bool      g_halted = false;
int       g_haltKind = 0;
datetime  g_week = 0;
double    g_weekEquity = 0;
int       g_tradesToday = 0;
datetime  g_pauseUntil = 0;
int       g_consec = 0;
double    g_roll[];

int       g_nwS[], g_nwE[];
bool      g_nwDay[7];
NewsEvt   g_news[];
bool      g_newsOK = false;
datetime  g_lastCalLoad = 0;
datetime  g_lastSave = 0;
datetime  g_lastCleanup = 0;
string    g_setupTag = "";
double    g_mrTarget = 0.0;
double    g_lastER = 0.0, g_lastRatio = 0.0;

#define REJ_SPREAD     0
#define REJ_CALENDAR   1
#define REJ_SAMEDIR    2
#define REJ_STOPS      3
#define REJ_COST       4
#define REJ_LOTS       5
#define REJ_PORTFOLIO  6
#define REJ_EXPOSURE   7
#define REJ_STALE      8
#define REJ_CORR       9
#define REJ_N          10

struct Cand {
   int      si;
   int      dir;
   double   score;
   double   thr;
   double   rm;
   double   adx;
   double   er;
   double   atrRatio;
   double   atr;
   double   mrTarget;
   string   tag;
   datetime bar;
};
Cand      g_cand[];
datetime  g_candFirst = 0;

// Signaux trop étendus mis en attente : aucune entrée immédiate.
// Ils ne seront rejoués que si le prix retrace puis repart dans le sens du signal.
struct PendingPullback {
   Cand     c;
   double   extreme;
   double   lastPrice;
   datetime created;
   bool     retraced;
};
PendingPullback g_pullbacks[];
int       g_rej[REJ_N];
datetime  g_lastRejLog = 0;
int       g_badFills = 0;

// Profiles scale the requested risk, but never bypass user/broker hard limits.
// SAFE/BALANCED/DYNAMIC apply profile-specific hard ceilings. CUSTOM uses the configured caps.
bool IsSafeProfile() { return(g_activeRiskProfile == CLY_RISK_SAFE); }
double ProfileRiskMultiplier() {
   if(g_activeRiskProfile == CLY_RISK_BALANCED) return(1.25);
   if(g_activeRiskProfile == CLY_RISK_DYNAMIC) return(1.50);
   return(1.0);
}
string RiskProfileName() {
   if(g_activeRiskProfile == CLY_RISK_SAFE) return("SAFE");
   if(g_activeRiskProfile == CLY_RISK_BALANCED) return("BALANCED");
   if(g_activeRiskProfile == CLY_RISK_DYNAMIC) return("DYNAMIC");
   return("CUSTOM");
}
// Hard ceilings by profile. User inputs can make these limits stricter, never looser.
double ProfileTradeRiskCeiling() {
   if(g_activeRiskProfile == CLY_RISK_SAFE) return(0.25);
   if(g_activeRiskProfile == CLY_RISK_BALANCED) return(0.35);
   if(g_activeRiskProfile == CLY_RISK_DYNAMIC) return(0.50);
   return(g_effMaxRiskPerTrade);
}
double EffectiveRiskPerTradePct() { return(MathMin(g_effMaxRiskPerTrade,ProfileTradeRiskCeiling())); }
double EffectiveTotalRiskPct() {
   double cap=g_effMaxTotalRiskPct;
   if(g_activeRiskProfile==CLY_RISK_SAFE) cap=MathMin(cap,0.75);
   else if(g_activeRiskProfile==CLY_RISK_BALANCED) cap=MathMin(cap,1.00);
   else if(g_activeRiskProfile==CLY_RISK_DYNAMIC) cap=MathMin(cap,1.25);
   return(cap);
}
double EffectiveCurrencyRiskPct() {
   double cap=g_effMaxCurrencyRiskPct;
   if(g_activeRiskProfile==CLY_RISK_SAFE) cap=MathMin(cap,0.50);
   else if(g_activeRiskProfile==CLY_RISK_BALANCED) cap=MathMin(cap,0.65);
   else if(g_activeRiskProfile==CLY_RISK_DYNAMIC) cap=MathMin(cap,0.75);
   return(cap);
}
double EffectiveDailyLossPct() {
   double cap=g_effMaxDailyLossPct;
   if(g_activeRiskProfile==CLY_RISK_SAFE) cap=(cap>0?MathMin(cap,1.50):1.50);
   else if(g_activeRiskProfile==CLY_RISK_BALANCED) cap=(cap>0?MathMin(cap,2.00):2.00);
   else if(g_activeRiskProfile==CLY_RISK_DYNAMIC) cap=(cap>0?MathMin(cap,2.50):2.50);
   return(cap);
}
double EffectiveWeeklyLossPct() {
   double cap=g_effMaxWeeklyLossPct;
   if(g_activeRiskProfile==CLY_RISK_SAFE) cap=(cap>0?MathMin(cap,3.00):3.00);
   else if(g_activeRiskProfile==CLY_RISK_BALANCED) cap=(cap>0?MathMin(cap,4.00):4.00);
   else if(g_activeRiskProfile==CLY_RISK_DYNAMIC) cap=(cap>0?MathMin(cap,5.00):5.00);
   return(cap);
}
double EffectiveMarginUsePct() {
   double cap=InpMaxMarginUsePct;
   if(g_activeRiskProfile==CLY_RISK_SAFE) cap=MathMin(cap,20.0);
   else if(g_activeRiskProfile==CLY_RISK_BALANCED) cap=MathMin(cap,25.0);
   else if(g_activeRiskProfile==CLY_RISK_DYNAMIC) cap=MathMin(cap,30.0);
   return(cap);
}
int EffectiveMaxOpenTrades() {
   if(g_activeRiskProfile==CLY_RISK_SAFE) return((int)MathMin(g_effMaxOpenTrades,2));
   if(g_activeRiskProfile==CLY_RISK_BALANCED) return((int)MathMin(g_effMaxOpenTrades,3));
   if(g_activeRiskProfile==CLY_RISK_DYNAMIC) return((int)MathMin(g_effMaxOpenTrades,4));
   return(g_effMaxOpenTrades);
}
int EffectiveMaxSameDirection() {
   if(g_activeRiskProfile==CLY_RISK_SAFE) return((int)MathMin(g_effMaxSameDirection,1));
   if(g_activeRiskProfile==CLY_RISK_BALANCED) return((int)MathMin(g_effMaxSameDirection,2));
   if(g_activeRiskProfile==CLY_RISK_DYNAMIC) return((int)MathMin(g_effMaxSameDirection,2));
   return(g_effMaxSameDirection);
}
int EffectiveMaxTradesPerDay() {
   if(g_activeRiskProfile==CLY_RISK_SAFE) return(g_effMaxTradesPerDay>0?(int)MathMin(g_effMaxTradesPerDay,4):4);
   if(g_activeRiskProfile==CLY_RISK_BALANCED) return(g_effMaxTradesPerDay>0?(int)MathMin(g_effMaxTradesPerDay,6):6);
   if(g_activeRiskProfile==CLY_RISK_DYNAMIC) return(g_effMaxTradesPerDay>0?(int)MathMin(g_effMaxTradesPerDay,8):8);
   return(g_effMaxTradesPerDay);
}
int EffectiveMaxTradesPerSymbol() {
   if(g_activeRiskProfile==CLY_RISK_SAFE) return(InpMaxTradesPerSymbol>0?(int)MathMin(InpMaxTradesPerSymbol,1):1);
   if(g_activeRiskProfile==CLY_RISK_BALANCED) return(InpMaxTradesPerSymbol>0?(int)MathMin(InpMaxTradesPerSymbol,2):2);
   if(g_activeRiskProfile==CLY_RISK_DYNAMIC) return(InpMaxTradesPerSymbol>0?(int)MathMin(InpMaxTradesPerSymbol,2):2);
   return(InpMaxTradesPerSymbol);
}

//======================== UTILITAIRES ========================
uint ServerHash() {
   string server = AccountInfoString(ACCOUNT_SERVER);
   uint h = 2166136261;
   for(int i=0; i<StringLen(server); i++) { h ^= (uchar)StringGetCharacter(server,i); h *= 16777619; }
   return h;
}
string K(const string s) {
   return "CLYMO_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
          IntegerToString((long)ServerHash()) + "_" + IntegerToString((long)InpMagic) + "_" + s;
}

string KP(const string s, const ulong pid) { return K(s + "_" + IntegerToString((long)pid)); }

double GVGet(const string key, const double def) {
   if(!GlobalVariableCheck(key)) return(def);
   return(GlobalVariableGet(key));
}

datetime DayStart(const datetime t) {
   MqlDateTime d;
   if(!TimeToStruct(t, d)) return(t);
   d.hour = 0; d.min = 0; d.sec = 0;
   return StructToTime(d);
}

int MinOfDay(const datetime t) {
   MqlDateTime d; TimeToStruct(t, d);
   return(d.hour * 60 + d.min);
}

void Log(const string msg) { if(InpVerbose) Print("BLACKHIPPO | ", msg); }

int VolDigits(const double step) {
   int d = 0;
   while(d < 8 && MathAbs(step * MathPow(10, d) - MathRound(step * MathPow(10, d))) > 1e-9) d++;
   return(d);
}

double TickValue(const string sym) {
   double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0) tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   return(tv);
}

bool IsHedgingAccount() {
   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}

double NormalizePriceTick(const string sym, const double price) {
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(tick <= 0) return NormalizeDouble(price, digits);
   return NormalizeDouble(MathRound(price / tick) * tick, digits);
}

double LossAtStop(const string sym, const bool buy, const double open,
                  const double sl, const double volume) {
   if(volume <= 0 || open <= 0 || sl <= 0) return 0.0;
   double profit = 0.0;
   ENUM_ORDER_TYPE type = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type, sym, volume, open, sl, profit)) return -1.0;
   return MathMax(0.0, -profit);
}

bool Buf(const int h, const int buffer, const int shift, const int count, double &out[]) {
   if(h == INVALID_HANDLE) return(false);
   ArraySetAsSeries(out, true);
   if(CopyBuffer(h, buffer, shift, count, out) != count) return(false);
   return(true);
}

bool Val(const int h, const int shift, double &v, const int buffer = 0) {
   double a[];
   if(!Buf(h, buffer, shift, 1, a)) return(false);
   v = a[0];
   return(v != EMPTY_VALUE && MathIsValidNumber(v));
}

bool TradingAllowed() {
   return(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) != 0 &&
          AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0 &&
          AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0 &&
          TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
}

int SymIndex(const string sym) {
   for(int i = 0; i < g_n; i++) if(g_s[i].name == sym) return(i);
   return(-1);
}

// Spread regime filter based on completed M1 bars. The absolute spread and
// ATR-relative limits remain authoritative; percentile history is an extra veto.
// Le seuil est calculé une fois par barre M1 et par symbole (cache), pas à chaque tick.
string   g_spSym[];
datetime g_spBar[];
double   g_spLimit[];

// Retourne false si le seuil est indisponible/non informatif (le filtre est alors ignoré : fail-open
// uniquement pour ce filtre adaptatif, les limites dures de spread restent actives).
bool SpreadPercentileLimit(const string sym, double &limit) {
   limit = 0.0;
   datetime bar = iTime(sym, PERIOD_M1, 0);
   int idx = -1;
   for(int i = 0; i < ArraySize(g_spSym); i++) if(g_spSym[i] == sym) { idx = i; break; }
   if(idx >= 0 && bar > 0 && g_spBar[idx] == bar) { limit = g_spLimit[idx]; return(limit > 0.0); }

   double lim = 0.0;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(sym, PERIOD_M1, 1, 120, rates);
   if(copied >= 30) {
      double samples[];
      ArrayResize(samples, copied);
      int n = 0;
      for(int i = 0; i < copied; i++) {
         if(rates[i].spread < 0) continue;
         samples[n++] = (double)rates[i].spread;
      }
      if(n >= 30) {
         ArrayResize(samples, n);
         ArraySort(samples);
         int q = (int)MathFloor(InpSpreadPctileMax * (n - 1));
         q = (int)MathMax(0, MathMin(n - 1, q));
         lim = samples[q];   // un historique nul n'est pas informatif : lim<=0 => filtre ignoré
      }
   }
   if(idx < 0) {
      idx = ArraySize(g_spSym);
      ArrayResize(g_spSym, idx + 1); ArrayResize(g_spBar, idx + 1); ArrayResize(g_spLimit, idx + 1);
      g_spSym[idx] = sym;
   }
   g_spBar[idx] = bar;
   g_spLimit[idx] = lim;
   limit = lim;
   return(lim > 0.0);
}

bool SpreadPercentileAllowed(const string sym, const double currentSpreadPoints) {
   if(InpSpreadPctileMax <= 0.0) return(true);
   double limit;
   if(!SpreadPercentileLimit(sym, limit)) return(true);
   return(currentSpreadPoints <= limit + 0.5);
}

// Corrélation Pearson sur rendements logarithmiques M15 clôturés.
// Le signe combiné corrélation × direction permet d'identifier une exposition
// factorielle alignée, y compris lorsque les directions de position diffèrent.
#define CORR_UNKNOWN -9.0   // donnée indisponible (distinct d'une vraie corrélation nulle)
double SymbolCorrelation(const string sym1, const string sym2) {
   if(sym1 == sym2) return(1.0);
   const int bars=41; // 40 rendements sur 41 clôtures synchronisées
   double c1[], c2[];
   ArraySetAsSeries(c1,true);
   ArraySetAsSeries(c2,true);
   if(CopyClose(sym1,PERIOD_M15,1,bars,c1)!=bars) return(CORR_UNKNOWN);
   if(CopyClose(sym2,PERIOD_M15,1,bars,c2)!=bars) return(CORR_UNKNOWN);
   double r1[],r2[];
   ArrayResize(r1,bars-1); ArrayResize(r2,bars-1);
   double m1=0.0,m2=0.0;
   for(int i=0;i<bars-1;i++) {
      if(c1[i]<=0.0 || c1[i+1]<=0.0 || c2[i]<=0.0 || c2[i+1]<=0.0) return(CORR_UNKNOWN);
      r1[i]=MathLog(c1[i]/c1[i+1]);
      r2[i]=MathLog(c2[i]/c2[i+1]);
      m1+=r1[i]; m2+=r2[i];
   }
   const int n=bars-1;
   m1/=n; m2/=n;
   double cov=0.0,v1=0.0,v2=0.0;
   for(int j=0;j<n;j++) {
      double a=r1[j]-m1, b=r2[j]-m2;
      cov+=a*b; v1+=a*a; v2+=b*b;
   }
   double den=MathSqrt(v1*v2);
   if(den<=1e-14) return(0.0);
   return(MathMax(-1.0,MathMin(1.0,cov/den)));
}

bool CorrelationOK(const string candidate, const int dir) {
   if(InpMaxCorrelation<=0.0 || InpMaxCorrelation>=1.0) return(true);
   for(int i=PositionsTotal()-1;i>=0;i--) {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string openSym=PositionGetString(POSITION_SYMBOL);
      int openDir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      if(openSym==candidate) continue;
      double corr=SymbolCorrelation(candidate,openSym);
      if(corr<=-5.0) { // fail-closed : impossible de mesurer le recoupement => pas de nouvelle entrée
         Log("Corrélation indisponible "+candidate+"/"+openSym+" : entrée refusée par prudence");
         return(false);
      }
      // Alignement des expositions : BUY+BUY sur corr positive, BUY+SELL
      // sur corr négative. Une simple corrélation absolue sur-dirigeait le filtre.
      if(corr*(double)dir*(double)openDir>=InpMaxCorrelation) return(false);
   }
   return(true);
}

//======================== CSV ========================
string CsvField(string value) {
   StringReplace(value, "\"", "\"\"");
   if(StringFind(value, ",") >= 0 || StringFind(value, "\"") >= 0 ||
      StringFind(value, "\r") >= 0 || StringFind(value, "\n") >= 0)
      return("\"" + value + "\"");
   return(value);
}

void Csv(const string ev, const string sym, const double lots, const double price,
         const double sl, const double tp, const double net, const double rReal, const string note) {
   if(!InpCSV || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   int h = FileOpen(InpCSVFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) { Log("CSV indisponible, erreur=" + IntegerToString(GetLastError())); return; }
   if(FileSize(h) == 0)
      FileWriteString(h, "time,event,symbol,lots,price,sl,tp,net,R,note\r\n");
   FileSeek(h, 0, SEEK_END);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(digits < 0 || digits > 12) digits = _Digits;
   string line = CsvField(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)) + "," +
                 CsvField(ev) + "," + CsvField(sym) + "," +
                 DoubleToString(lots, VolDigits(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP))) + "," +
                 DoubleToString(price, digits) + "," + DoubleToString(sl, digits) + "," +
                 DoubleToString(tp, digits) + "," + DoubleToString(net, 2) + "," +
                 DoubleToString(rReal, 2) + "," + CsvField(note) + "\r\n";
   FileWriteString(h, line);
   FileClose(h);
}

//======================== ÉTAT PERSISTANT ========================
datetime WeekStart(const datetime t) {
   datetime d = DayStart(t);
   MqlDateTime s; TimeToStruct(d, s);
   int back = (s.day_of_week + 6) % 7;
   for(int i = 0; i < back; i++) d = DayStart(d - 12 * 3600);
   return(d);
}

void SaveState() {
   if(MQLInfoInteger(MQL_TESTER)) { g_lastSave = TimeCurrent(); return; }
   GlobalVariableSet(K("day"), (double)g_day);
   GlobalVariableSet(K("dayeq"), g_dayEquity);
   GlobalVariableSet(K("week"), (double)g_week);
   GlobalVariableSet(K("weekeq"), g_weekEquity);
   GlobalVariableSet(K("peak"), g_peak);
   GlobalVariableSet(K("halted"), g_halted ? 1.0 : 0.0);
   GlobalVariableSet(K("hkind"), (double)g_haltKind);
   GlobalVariableSet(K("trades"), (double)g_tradesToday);
   GlobalVariableSet(K("pause"), (double)g_pauseUntil);
   GlobalVariableSet(K("consec"), (double)g_consec);
   for(int i = 0; i < g_n; i++) {
      GlobalVariableSet(K("st_" + g_s[i].name), (double)g_s[i].tradesToday);
      GlobalVariableSet(K("le_" + g_s[i].name), (double)g_s[i].lastEntryBar);
      GlobalVariableSet(K("lk_" + g_s[i].name), (double)g_s[i].lockUntil);
   }
   g_lastSave = TimeCurrent();
}

void Halt(const int kind) {
   // Une halte bloque déjà les entrées via g_halted. Le désarmement n'est conservé que pour la halte
   // critique, ou en live si InpHaltRequiresManualRearm=true. Sinon l'EA reprend seul au jour/à la
   // semaine suivante (et le Strategy Tester, sans dashboard, ne reste plus bloqué à vie).
   if(kind == HALT_CRITICAL || (InpHaltRequiresManualRearm && !MQLInfoInteger(MQL_TESTER))) g_entriesArmed = false;
   g_halted = true;
   g_haltKind = kind;
   SaveState();
}

void LoadState() {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime now = TimeCurrent();
   datetime today = DayStart(now), wk = WeekStart(now);
   g_peak = (!InpResetPeakOnInit && GlobalVariableCheck(K("peak"))) ? GlobalVariableGet(K("peak")) : eq;
   if(g_peak < eq) g_peak = eq;
   g_day = today;
   g_week = wk;
   bool sameDay  = GlobalVariableCheck(K("day"))  && (datetime)(long)GlobalVariableGet(K("day"))  == today;
   bool sameWeek = GlobalVariableCheck(K("week")) && (datetime)(long)GlobalVariableGet(K("week")) == wk;
   g_weekEquity = sameWeek ? GVGet(K("weekeq"), eq) : eq;
   g_haltKind   = (int)GVGet(K("hkind"), 0);
   bool wasHalted = (GVGet(K("halted"), 0) > 0.5);
   if(sameDay) {
      g_dayEquity   = GVGet(K("dayeq"), eq);
      g_tradesToday = (int)GVGet(K("trades"), 0);
      for(int i = 0; i < g_n; i++) {
         g_s[i].tradesToday = (int)GVGet(K("st_" + g_s[i].name), 0);
         g_s[i].lastEntryBar = (datetime)(long)GVGet(K("le_" + g_s[i].name), 0);
      }
   } else {
      g_dayEquity = eq; g_tradesToday = 0;
   }
   g_halted = false;
   if(wasHalted) {
      if(g_haltKind == HALT_CRITICAL) g_halted = true;
      else if(g_haltKind == HALT_WEEKLY && sameWeek) g_halted = true;
      else if(sameDay) g_halted = true;
   }
   if(!g_halted) g_haltKind = HALT_NONE;
   for(int i = 0; i < g_n; i++)
      g_s[i].lockUntil = (datetime)(long)GVGet(K("lk_" + g_s[i].name), 0);
   g_pauseUntil = (datetime)(long)GVGet(K("pause"), 0);
   g_consec     = sameDay ? (int)GVGet(K("consec"), 0) : 0;
}

void NewDayCheck() {
   datetime now = TimeCurrent();
   datetime d = DayStart(now);
   if(d == g_day) return;
   g_day = d;
   g_dayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime wk = WeekStart(now);
   if(wk != g_week) {
      g_week = wk;
      g_weekEquity = g_dayEquity;
      if(g_haltKind == HALT_WEEKLY) { g_halted = false; g_haltKind = HALT_NONE; }
   }
   if(g_haltKind != HALT_CRITICAL && g_haltKind != HALT_WEEKLY) { g_halted = false; g_haltKind = HALT_NONE; }
   g_tradesToday = 0;
   g_consec = 0;
   g_badFills = 0;
   for(int i = 0; i < g_n; i++) g_s[i].tradesToday = 0;
   SaveState();
   Log("Nouveau jour | equity ref=" + DoubleToString(g_dayEquity, 2));
}

bool PositionIsOpen(const ulong pid) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == pid) return(true);
   }
   return(false);
}

void CleanupGVs() {
   string prefixes[10] = {"R0_", "RM_", "P1_", "AS_", "PR_", "ST_",
                           "PP_", "PV_", "PC_", "PT_"};
   string base = K("");
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--) {
      string name = GlobalVariableName(i);
      if(StringFind(name, base) != 0) continue;
      string rest = StringSubstr(name, StringLen(base));
      for(int p = 0; p < ArraySize(prefixes); p++) {
         if(StringFind(rest, prefixes[p]) == 0) {
            ulong pid = (ulong)StringToInteger(StringSubstr(rest, StringLen(prefixes[p])));
            if(pid > 0 && !PositionIsOpen(pid)) GlobalVariableDel(name);
            break;
         }
      }
   }
   g_lastCleanup = TimeCurrent();
}

//======================== HISTORIQUE / STATS ========================
bool PositionNet(const ulong pid, double &net, bool &closed) {
   net = 0; closed = false;
   if(!HistorySelectByPosition(pid)) return(false);
   double vIn = 0, vOut = 0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
             HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      long en = HistoryDealGetInteger(d, DEAL_ENTRY);
      double v = HistoryDealGetDouble(d, DEAL_VOLUME);
      if(en == DEAL_ENTRY_IN) vIn += v;
      else if(en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_OUT_BY || en == DEAL_ENTRY_INOUT) vOut += v;
   }
   closed = (vIn > 0 && vOut >= vIn - 1e-8);
   return(true);
}

void PushRoll(const double net) {
   int n = ArraySize(g_roll);
   if(InpRollTrades <= 0) return;
   if(n >= InpRollTrades) {
      for(int i = 1; i < n; i++) g_roll[i - 1] = g_roll[i];
      g_roll[n - 1] = net;
   } else {
      ArrayResize(g_roll, n + 1);
      g_roll[n] = net;
   }
}

void RebuildStats() {
   ArrayResize(g_roll, 0);
   if(!HistorySelect(TimeCurrent() - 90 * 86400, TimeCurrent() + 86400)) return;
   ulong pids[];
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      long en = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_OUT_BY && en != DEAL_ENTRY_INOUT) continue;
      ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      bool found = false;
      for(int k = 0; k < ArraySize(pids); k++) if(pids[k] == pid) { found = true; break; }
      if(!found) { ArrayResize(pids, ArraySize(pids) + 1); pids[ArraySize(pids) - 1] = pid; }
   }
   int total = ArraySize(pids);
   int from = MathMax(0, total - InpRollTrades);
   for(int i = from; i < total; i++) {
      double net; bool closed;
      if(PositionNet(pids[i], net, closed) && closed) PushRoll(net);
   }
   Log("Stats reconstruites | trades=" + IntegerToString(ArraySize(g_roll)));
}

double PFMult() {
   if(!InpUseRollingPF) return(1.0);
   int n = ArraySize(g_roll);
   if(n < InpPFMinTrades) return(1.0);
   double gp = 0, gl = 0;
   for(int i = 0; i < n; i++) { if(g_roll[i] >= 0) gp += g_roll[i]; else gl += -g_roll[i]; }
   if(gl <= 0.01) return(gp > 0.01 ? InpPFGoodMult : 1.0);
   double pf = gp / gl;
   if(pf < InpPFLow) return(InpPFLowMult);
   if(pf >= InpPFGood) return(InpPFGoodMult);
   return(1.0);
}

double DDMult() {
   if(!InpUseDDScaling || g_peak <= 0) return(1.0);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_peak - eq) / g_peak * 100.0;
   if(dd <= InpDDStartPct) return(1.0);
   if(dd >= InpDDFullPct) return(InpDDFloorMult);
   return(1.0 - (1.0 - InpDDFloorMult) * (dd - InpDDStartPct) / (InpDDFullPct - InpDDStartPct));
}

// multiplicateur de régime (TREND / RANGE / HIGH_VOL / TRANSITION)
double RegimeMult(const double adx, const double er, const double atrRatio) {
   if(!InpUseRegimeEngine) return(1.0);
   if(atrRatio >= InpHighVolATRRatio) return(InpRegimeRiskHighVol);
   if(adx >= InpTrendADXFloor && er >= InpMinER) return(InpRegimeRiskTrend);
   if(adx <= InpRangeADXCeil && er <= InpMRERMax) return(InpRegimeRiskRange);
   return(InpRegimeRiskTrans);
}

// volatility targeting — module la taille selon le budget de risque journalier restant :
// jusqu'à InpVolTargetCeil quand rien n'est consommé, jusqu'à InpVolTargetFloor quand il est épuisé.
// (le plafond dur par trade du profil reste toujours appliqué après coup)
double VolTargetMult() {
   if(!InpUseVolTargeting || g_dayEquity <= 0 || InpDailyRiskBudgetPct <= 0) return(1.0);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayLossPct = (g_dayEquity - eq) / g_dayEquity * 100.0;   // >0 = perte
   // risque déjà "consommé" = perte réalisée + risque flottant approximé
   double openRisk = OpenRiskTotal();
   double consumed = MathMax(0.0, dayLossPct) + (openRisk / g_dayEquity * 100.0);
   if(consumed <= 0.0) return(InpVolTargetCeil);
   double remaining = InpDailyRiskBudgetPct - consumed;
   if(remaining <= 0.0) return(InpVolTargetFloor);
   double ratio = remaining / InpDailyRiskBudgetPct;
   return(MathMax(InpVolTargetFloor, MathMin(InpVolTargetCeil, ratio * 1.15)));
}

//======================== FILTRES TEMPORELS / NEWS ========================
int HM(string x) {
   StringTrimLeft(x); StringTrimRight(x);
   string p[];
   if(StringSplit(x, ':', p) != 2) return(-1);
   int hh=(int)StringToInteger(p[0]), mm=(int)StringToInteger(p[1]);
   if(hh<0 || hh>23 || mm<0 || mm>59) return(-1);
   return(hh*60+mm);
}

void ParseNewsDays(const string str) {
   for(int i = 0; i < 7; i++) g_nwDay[i] = false;
   string p[];
   int n = StringSplit(str, ',', p);
   for(int i = 0; i < n; i++) {
      StringTrimLeft(p[i]); StringTrimRight(p[i]);
      if(p[i] == "") continue;
      int d = (int)StringToInteger(p[i]);
      if(d >= 0 && d <= 6) g_nwDay[d] = true;
   }
}

void ParseWindows(const string str) {
   ArrayResize(g_nwS, 0); ArrayResize(g_nwE, 0);
   string items[];
   int n = StringSplit(str, ',', items);
   for(int i = 0; i < n; i++) {
      string ab[];
      if(StringSplit(items[i], '-', ab) != 2) continue;
      int a = HM(ab[0]), b = HM(ab[1]);
      if(a < 0 || b < 0) continue;
      int k = ArraySize(g_nwS);
      ArrayResize(g_nwS, k + 1); ArrayResize(g_nwE, k + 1);
      g_nwS[k] = a; g_nwE[k] = b;
   }
}

bool InNewsWindow() {
   if(!InpUseNewsWindows) return(false);
   MqlDateTime nd; TimeToStruct(TimeCurrent(), nd);
   if(!g_nwDay[nd.day_of_week]) return(false);
   int m = nd.hour * 60 + nd.min;
   int buffer = MathMax(0, InpNewsBufferMin);
   for(int i = 0; i < ArraySize(g_nwS); i++) {
      int start = g_nwS[i];
      int finish = g_nwE[i];
      int duration = (finish - start + 1440) % 1440;
      if(duration == 0) duration = 1440;
      int rel = (m - start + 1440) % 1440;
      if(rel <= duration) return(true);
      int before = (start - m + 1440) % 1440;
      int after  = (m - finish + 1440) % 1440;
      if(before <= buffer || after <= buffer) return(true);
   }
   return(false);
}

bool DownloadCalendarWeb() {
   if(!InpUseCalendarWebRequest) return(false);
   if(MQLInfoInteger(MQL_TESTER)) {
      Log("WebRequest indisponible dans le Strategy Tester; utiliser un CSV historique.");
      return(false);
   }
   g_lastCalLoad = TimeCurrent();
   if(StringLen(InpCalendarURL) < 8) {
      Log("WebRequest calendrier activé mais InpCalendarURL est vide/invalide.");
      return(false);
   }

   char requestData[], response[];
   string responseHeaders;
   ArrayResize(requestData, 0);
   ResetLastError();
   int http = WebRequest("GET", InpCalendarURL,
                         "Accept: text/csv\r\nUser-Agent: CLY-MO-Pro/001\r\n",
                         InpCalendarTimeoutMs, requestData, response, responseHeaders);
   if(http != 200) {
      int err = GetLastError();
      Log("Échec WebRequest calendrier: HTTP=" + IntegerToString(http) +
          " erreur=" + IntegerToString(err) + ". Conservation du dernier CSV.");
      return(false);
   }

   int responseBytes=ArraySize(response);
   if(responseBytes < 10 || responseBytes > 1048576) {
      Log("Taille de réponse calendrier invalide; cache conservé.");
      return(false);
   }
   string csv = CharArrayToString(response, 0, WHOLE_ARRAY, CP_UTF8);
   StringTrimLeft(csv); StringTrimRight(csv);
   string lower=csv; StringToLower(lower);
   if(StringLen(csv) < 10 || StringFind(lower, "<html") >= 0 || StringFind(lower, "<!doctype") >= 0) {
      Log("Réponse calendrier vide ou HTML au lieu d'un CSV; cache conservé.");
      return(false);
   }
   string rows[]; ushort nl=StringGetCharacter("\n",0);
   int rowCount=StringSplit(csv,nl,rows), validRows=0;
   for(int r=0;r<rowCount;r++) {
      StringTrimLeft(rows[r]); StringTrimRight(rows[r]);
      if(rows[r]=="") continue;
      string fields[];
      if(StringSplit(rows[r],',',fields)<3) continue;
      StringTrimLeft(fields[0]); StringTrimRight(fields[0]);
      StringTrimLeft(fields[1]); StringTrimRight(fields[1]);
      StringTrimLeft(fields[2]); StringTrimRight(fields[2]);
      datetime eventTime=StringToTime(fields[0]);
      StringToUpper(fields[1]);
      int impact=(int)StringToInteger(fields[2]);
      if(eventTime>0 && StringLen(fields[1])==3 && impact>=1 && impact<=3) validRows++;
   }
   if(validRows==0) {
      Log("CSV calendrier non conforme (attendu: YYYY.MM.DD HH:MM,CUR,IMPACT); cache conservé.");
      return(false);
   }

   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if(InpCalendarCommon) flags |= FILE_COMMON;
   int h = FileOpen(InpCalendarFile, flags);
   if(h == INVALID_HANDLE) {
      Log("Impossible d'écrire le CSV calendrier. Erreur=" + IntegerToString(GetLastError()));
      return(false);
   }
   FileWriteString(h, csv);
   FileClose(h);
   Log("CSV calendrier téléchargé: " + IntegerToString(StringLen(csv)) + " caractères.");
   return(true);
}

bool LoadNativeCalendar() {
   g_lastCalLoad = TimeCurrent();
   ArrayResize(g_news, 0);
   g_newsOK = false;
   if(MQLInfoInteger(MQL_TESTER)) {
      Log("Calendrier natif MT5 indisponible dans le Strategy Tester; utiliser le CSV historique.");
      return(false);
   }
   datetime now = TimeTradeServer();
   if(now <= 0) now = TimeCurrent();
   datetime from = now - 2 * 3600;
   datetime to   = now + 7 * 86400;
   string currencies[];
   for(int i=0; i<g_n; i++) {
      string pair[2]; pair[0] = g_s[i].base; pair[1] = g_s[i].quote;
      for(int j=0; j<2; j++) {
         bool exists=false;
         for(int k=0; k<ArraySize(currencies); k++) if(currencies[k]==pair[j]) { exists=true; break; }
         if(!exists && StringLen(pair[j])==3) {
            int n=ArraySize(currencies); ArrayResize(currencies,n+1); currencies[n]=pair[j];
         }
      }
   }
   int loaded=0, successfulQueries=0;
   for(int c=0; c<ArraySize(currencies); c++) {
      MqlCalendarValue values[];
      ResetLastError();
      // CalendarValueHistory renvoie un bool (pas un nombre) : le nombre d'événements vient d'ArraySize().
      bool calOK=CalendarValueHistory(values, from, to, NULL, currencies[c]);
      int count=(calOK ? ArraySize(values) : 0);
      if(!calOK || count<=0) {
         // 7 jours sans aucun événement = base non synchronisée ou devise non couverte (ex. XAU) :
         // on ne la compte pas comme requête valide, sinon le filtre news serait aveugle sans le dire.
         Log("Calendrier MT5 sans données exploitables pour "+currencies[c]+" (erreur="+IntegerToString(GetLastError())+") : devise non couverte par le filtre news.");
         continue;
      }
      successfulQueries++;
      for(int v=0; v<count; v++) {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[v].event_id, ev)) continue;
         int impact=0;
         if(ev.importance==CALENDAR_IMPORTANCE_HIGH) impact=3;
         else if(ev.importance==CALENDAR_IMPORTANCE_MODERATE) impact=2;
         else if(ev.importance==CALENDAR_IMPORTANCE_LOW) impact=1;
         if(impact < InpCalMinImpact) continue;
         int n=ArraySize(g_news); ArrayResize(g_news,n+1);
         g_news[n].t=values[v].time; g_news[n].ccy=currencies[c]; g_news[n].impact=impact;
         g_news[n].allDay=(ev.time_mode!=CALENDAR_TIMEMODE_DATETIME);
         loaded++;
      }
   }
   g_newsOK=(successfulQueries>0);
   if(g_newsOK) Log("Calendrier natif MT5 valide: "+IntegerToString(loaded)+" événements filtrés.");
   else Log("Calendrier natif MT5 inaccessible; source non validée.");
   return(g_newsOK);
}

void LoadCalendar() {
   g_lastCalLoad = TimeCurrent();
   g_newsOK = false;
   ArrayResize(g_news, 0);
   int flags = FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   if(InpCalendarCommon) flags |= FILE_COMMON;
   int h = FileOpen(InpCalendarFile, flags);
   if(h == INVALID_HANDLE) return;
   if(InpRequireFreshCal && !MQLInfoInteger(MQL_TESTER)) {
      datetime mod = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
      if(TimeLocal() - mod > (datetime)(InpCalendarMaxAgeH * 3600)) { FileClose(h); return; }
   }
   while(!FileIsEnding(h)) {
      string line = FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(line == "") continue;
      string p[];
      if(StringSplit(line, ',', p) < 3) continue;
      StringTrimLeft(p[0]); StringTrimRight(p[0]);
      StringTrimLeft(p[1]); StringTrimRight(p[1]);
      StringTrimLeft(p[2]); StringTrimRight(p[2]);
      StringToUpper(p[1]);
      datetime t = StringToTime(p[0]);
      int impact = (int)StringToInteger(p[2]);
      if(t <= 0 || StringLen(p[1]) != 3 || impact < 1 || impact > 3)
         continue;
      int k = ArraySize(g_news);
      ArrayResize(g_news, k + 1);
      g_news[k].t = t;
      g_news[k].ccy = p[1];
      g_news[k].impact = impact;
      g_news[k].allDay = false;
   }
   FileClose(h);
   g_newsOK = (ArraySize(g_news) > 0);
   if(!g_newsOK) Log("Calendrier économique vide ou invalide : fail-closed=" + (InpFailClosedCalendar ? "true" : "false"));
}

bool CalendarBlocked(SymState &s) {
   if(!InpUseCalendarFile && !InpUseNativeCalendar && !InpUseCalendarWebRequest) return(false);
   if(MQLInfoInteger(MQL_TESTER) && !g_newsOK)
      return(InpTesterFailClosedCalendar);
   if(!g_newsOK) return(InpFailClosedCalendar);
   datetime now = (InpUseNativeCalendar ? TimeTradeServer() : TimeCurrent());
   if(now <= 0) now = TimeCurrent();
   for(int i = 0; i < ArraySize(g_news); i++) {
      if(g_news[i].impact < InpCalMinImpact) continue;
      if(g_news[i].ccy != s.base && g_news[i].ccy != s.quote) continue;
      if(g_news[i].allDay) {
         if(DayStart(now)==DayStart(g_news[i].t)) return(true);
      } else if(now >= g_news[i].t - InpCalMinBefore * 60 && now <= g_news[i].t + InpCalMinAfter * 60) return(true);
   }
   return(false);
}

bool NewsImminent(SymState &s, const int minutes) {
   if(!g_newsOK || minutes <= 0) return(false);
   datetime now = (InpUseNativeCalendar ? TimeTradeServer() : TimeCurrent());
   if(now <= 0) now = TimeCurrent();
   for(int i = 0; i < ArraySize(g_news); i++) {
      if(g_news[i].allDay || g_news[i].impact < InpCalMinImpact) continue;
      if(g_news[i].ccy != s.base && g_news[i].ccy != s.quote) continue;
      long dt = (long)g_news[i].t - (long)now;
      if(dt >= 0 && dt <= (long)minutes * 60) return(true);
   }
   return(false);
}

bool InTradingWindow() {
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   if(d.day_of_week == 0 || d.day_of_week == 6) return(false);
   int m = d.hour * 60 + d.min;
   int endH = (d.day_of_week == 5) ? InpFridayEndHour : InpEndHour;
   return(m >= InpStartHour * 60 + InpSkipOpenMin && m < endH * 60);
}

bool IsCloseTime() {
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   int m = d.hour * 60 + d.min;
   if(d.day_of_week == 5) return(m >= InpFridayCloseHour * 60 + InpFridayCloseMinute);
   return(m >= InpCloseHour * 60 + InpCloseMinute);
}

// Vérifie les restrictions directionnelles du symbole (FULL/LONGONLY/SHORTONLY).
bool CanTradeDirection(const string sym, const int dir) {
   long mode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_FULL) return(true);
   if(mode == SYMBOL_TRADE_MODE_LONGONLY) return(dir > 0);
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY) return(dir < 0);
   return(false);
}

//======================== PORTEFEUILLE ========================
double PosRiskMoney(const string sym, const bool buy, const double open, const double sl, const double vol) {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(sl <= 0) return(eq);
   // A stop beyond breakeven (BUY: SL >= open; SELL: SL <= open) protects
   // the entry price. It is not an equity-sized loss; count only the configured
   // commission allowance. A missing stop remains a conservative full-equity sentinel.
   double dist = buy ? (open - sl) : (sl - open);
   double commission = vol * MathMax(0.0, InpCommissionPerLot);
   if(!MathIsValidNumber(dist)) return(eq);
   if(dist <= 0.0) {
      MqlTick riskTick;
      if(!SymbolInfoTick(sym,riskTick) || riskTick.bid<=0.0 || riskTick.ask<=0.0) return(eq);
      // A profit-side stop still above/below the live market may be crossed or pending execution.
      if((buy && sl>=riskTick.bid) || (!buy && sl<=riskTick.ask)) return(eq);
      return(commission);
   }
   double loss = LossAtStop(sym, buy, open, sl, vol);
   // An impossible/zero calculation for a genuine loss-side stop is UNKNOWN.
   if(loss <= 0.0 || !MathIsValidNumber(loss)) return(eq);
   return(loss + commission);
}

bool IncludePortfolioPosition() {
   return(InpPortfolioAllPositions || PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

double OpenRiskTotal() {
   double r = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(!IncludePortfolioPosition()) continue;
      r += PosRiskMoney(PositionGetString(POSITION_SYMBOL),
                        PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY,
                        PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL),
                        PositionGetDouble(POSITION_VOLUME));
   }
   return(r);
}

double CcyExposure(const string ccy) {
   double x = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(!IncludePortfolioPosition()) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double r = PosRiskMoney(sym,
                              PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY,
                              PositionGetDouble(POSITION_PRICE_OPEN),
                              PositionGetDouble(POSITION_SL),
                              PositionGetDouble(POSITION_VOLUME));
      if(SymbolInfoString(sym, SYMBOL_CURRENCY_BASE) == ccy)   x += r;
      if(SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT) == ccy) x += r;
   }
   return(x);
}

// Proxy directionnel signé par devise. Le plafond brut ci-dessus reste actif
// en parallèle : les compensations ne peuvent donc pas masquer le risque brut.
double CcyExposureSigned(const string ccy) {
   double x=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--) {
      if(PositionGetTicket(i)==0) continue;
      if(!IncludePortfolioPosition()) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double r=PosRiskMoney(sym,buy,PositionGetDouble(POSITION_PRICE_OPEN),
                            PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_VOLUME));
      double d=buy?1.0:-1.0;
      if(SymbolInfoString(sym,SYMBOL_CURRENCY_BASE)==ccy) x+=d*r;
      if(SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT)==ccy) x-=d*r;
   }
   return(x);
}

bool ExposureOK(SymState &s, const int dir, const double risk) {
   double cap=AccountInfoDouble(ACCOUNT_EQUITY)*EffectiveCurrencyRiskPct()/100.0;
   // Limite brute conservatrice : ne crédite aucune compensation.
   if(CcyExposure(s.base)+risk>cap+0.01) return(false);
   if(CcyExposure(s.quote)+risk>cap+0.01) return(false);
   // Limite directionnelle signée : évite d'empiler le même facteur devise.
   double d=(dir>0)?1.0:-1.0;
   if(MathAbs(CcyExposureSigned(s.base)+d*risk)>cap+0.01) return(false);
   if(MathAbs(CcyExposureSigned(s.quote)-d*risk)>cap+0.01) return(false);
   return(true);
}

int CountOpen() {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic) c++;
   }
   return(c);
}

int CountDir(const int dir) {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      int d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(d == dir) c++;
   }
   return(c);
}

bool HasPosition(const string sym) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == sym) return(true);
   }
   return(false);
}

bool HasAnyPositionOnSymbol(const string sym) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==sym) return true;
   }
   return false;
}

//======================== ORDRES ========================
bool WaitPositionGone(const ulong tk) {
   for(int i = 0; i < 6; i++) {
      if(!PositionSelectByTicket(tk)) return(true);
      if(i < 5) Sleep(50);
   }
   return(!PositionSelectByTicket(tk));
}

bool WaitVolumeAtMost(const ulong tk, const double maxVol) {
   for(int i = 0; i < 6; i++) {
      if(PositionSelectByTicket(tk) && PositionGetDouble(POSITION_VOLUME) <= maxVol) return(true);
      if(i < 5) Sleep(50);
   }
   return(false);
}

bool ClosePos(const ulong tk, const string why) {
   for(int a = 0; a < InpMaxRetries; a++) {
      if(!PositionSelectByTicket(tk)) return(true);
      string sym = PositionGetString(POSITION_SYMBOL);
      g_trade.SetDeviationInPoints(InpMaxDeviation);
      g_trade.SetTypeFillingBySymbol(sym);
      bool sent = g_trade.PositionClose(tk);
      uint rc = g_trade.ResultRetcode();
      if(sent && rc == TRADE_RETCODE_DONE) {
         if(WaitPositionGone(tk)) { Log("Fermeture confirmée " + sym + " (" + why + ")"); return(true); }
      }
      Sleep(InpRetryDelayMs);
   }
   return(!PositionSelectByTicket(tk));
}

void CloseAll(const string why) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ClosePos(tk, why);
   }
}

bool ModSL(const ulong tk, const string sym, const bool buy, double newSL, const double curTP) {
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double stopsLvl = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
   double freeze = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL) * pt;
   newSL = NormalizePriceTick(sym, newSL);
   if(bid<=0 || ask<=0 || pt<=0) return false;
   if(buy) {
      if(newSL >= bid - stopsLvl - pt) return false;
      if(freeze > 0 && bid - newSL <= freeze) return false;
      if(freeze > 0 && curTP > 0 && curTP - bid <= freeze) return false;
   } else {
      if(newSL <= ask + stopsLvl + pt) return false;
      if(freeze > 0 && newSL - ask <= freeze) return false;
      if(freeze > 0 && curTP > 0 && ask - curTP <= freeze) return false;
   }
   if(!PositionSelectByTicket(tk)) return false;
   bool sent = g_trade.PositionModify(tk, newSL, curTP);
   uint rc = g_trade.ResultRetcode();
   if(!sent || rc != TRADE_RETCODE_DONE) return false;
   if(!PositionSelectByTicket(tk)) return false;
   return MathAbs(PositionGetDouble(POSITION_SL)-newSL) <= SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE)*0.5;
}

//======================== SIZING ========================
double CalcLots(SymState &s, const int dir, const double price, const double slDist,
                const double riskMult, const double adx, const double er,
                const double atrRatio, double chaseRiskFactor, double &riskMoney) {
   riskMoney = 0;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double ts = SymbolInfoDouble(s.name, SYMBOL_TRADE_TICK_SIZE);
   double tv = TickValue(s.name);
   if(eq <= 0 || ts <= 0 || tv <= 0 || slDist <= 0) return(0);

   double stopPrice = (dir > 0) ? price - slDist : price + slDist;
   double oneLotLoss = LossAtStop(s.name, dir > 0, price, stopPrice, 1.0);
   if(oneLotLoss <= 0) return(0);
   double lossPerLot = oneLotLoss + MathMax(0.0, InpCommissionPerLot);
   // Produit des multiplicateurs adaptatifs; le plancher est explicitement configurable.
   // Utiliser le régime du candidat concerné, pas des globals potentiellement écrasées
   // par l'évaluation d'un autre symbole pendant le scan multi-actifs.
   double mult = riskMult * DDMult() * PFMult() * RegimeMult(adx, er, atrRatio) * VolTargetMult();
   mult = MathMax(InpRiskMultFloor, mult);
   double riskPct = MathMin(g_effRiskPercent * ProfileRiskMultiplier() * mult, EffectiveRiskPerTradePct());
   riskPct *= MathMax(0.10, MathMin(1.0, chaseRiskFactor)); // ne jamais augmenter le risque via anti-poursuite
   double allowed = eq * riskPct / 100.0;

   double step = SymbolInfoDouble(s.name, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(s.name, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(s.name, SYMBOL_VOLUME_MAX);
   if(step <= 0 || vmin <= 0) return(0);

   double raw = allowed / lossPerLot;
   // Respecter le pas de volume même si le plafond broker (vmax) n'est pas
   // un multiple exact du volume step. Un simple MathMin(lots,vmax) suivi
   // de NormalizeDouble pouvait arrondir au-dessus de vmax.
   double brokerMaxLots = MathFloor(vmax / step + 1e-9) * step;
   if(brokerMaxLots < vmin - 1e-12) return(0);
   double lots = MathFloor(raw / step + 1e-9) * step;
   lots = MathMin(lots, brokerMaxLots);
   lots = NormalizeDouble(lots, VolDigits(step));
   if(lots < vmin - 1e-12 || lots > vmax + 1e-12) return(0);
   riskMoney = lots * lossPerLot;

   double margin = 0;
   ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot, s.name, lots, price, margin)) return(0);
   if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9) return(0);
   if((AccountInfoDouble(ACCOUNT_MARGIN) + margin) / eq * 100.0 > EffectiveMarginUsePct()) return(0);
   return(lots);
}

//======================== SIGNAL ========================
double Efficiency(const string sym, const ENUM_TIMEFRAMES tf, const int n) {
   double cl[];
   ArraySetAsSeries(cl, true);
   if(CopyClose(sym, tf, 1, n + 1, cl) != n + 1) return(0);
   double path = 0;
   for(int i = 0; i < n; i++) {
      if(cl[i] <= 0 || cl[i + 1] <= 0) return(0);
      path += MathAbs(cl[i] - cl[i + 1]);
   }
   if(path <= 0) return(0);
   return(MathAbs(cl[0] - cl[n]) / path);
}

int EvaluateTrendSignal(SymState &s, double &atr, double &adx, double &riskMult,
                       double &signalScore, double &scoreThreshold) {
   signalScore = 0.0;
   scoreThreshold = InpScoreBaseThreshold;
   g_setupTag = "";
   int need = MathMax(InpEMATrend, InpATRRefPeriod) +
              MathMax(MathMax(InpERLookback, InpScoreVolumeLookback), InpScoreStructureBars) + 25;
   if(Bars(s.name, InpEntryTF) < need || Bars(s.name, InpHigherTF) < InpEMAH1 + 10 ||
      Bars(s.name, InpConfirmTF) < InpEMAConfirm + 10) return(0);

   double emaF, emaS, emaT, atrRef, h1a, h1b, m15, adx3, diPlus, diMinus;
   if(!Val(s.hEmaF, 1, emaF) || !Val(s.hEmaS, 1, emaS) || !Val(s.hEmaT, 1, emaT) ||
      !Val(s.hAtr, 1, atr) || !Val(s.hAtrRef, 1, atrRef) || !Val(s.hAdx, 1, adx) ||
      !Val(s.hAdx, 3, adx3) || !Val(s.hAdx, 1, diPlus, 1) || !Val(s.hAdx, 1, diMinus, 2) ||
      !Val(s.hH1, 1, h1a) || !Val(s.hH1, 4, h1b) || !Val(s.hM15, 1, m15)) return(0);

   double rsi[];
   if(!Buf(s.hRsi, 0, 1, 4, rsi)) return(0);
   if(atr <= 0 || atrRef <= 0) return(0);

   double o = iOpen(s.name, InpEntryTF, 1);
   double h = iHigh(s.name, InpEntryTF, 1);
   double l = iLow(s.name, InpEntryTF, 1);
   double c = iClose(s.name, InpEntryTF, 1);
   double range = h - l;
   if(o <= 0 || h <= 0 || l <= 0 || c <= 0 || range <= 0) return(0);

   int dir = (emaF > emaS) ? 1 : ((emaF < emaS) ? -1 : 0);
   if(dir == 0) return(0);

   double ratio = atr / atrRef;
   g_lastRatio = ratio;
   if(InpUseATRRatioFilter && ratio > InpMaxATRRatio * InpHardATRRatioMult) return(0);
   if(InpUseCandleFilter && range > InpMaxSignalCandleATR * InpHardCandleMult * atr) return(0);
   if(InpUseExtensionFilter && MathAbs(c - emaF) > InpMaxExtensionATR * InpHardExtensionMult * atr) return(0);

   double er = Efficiency(s.name, InpEntryTF, InpERLookback);
   g_lastER = er;
   double cH = iClose(s.name, InpHigherTF, 1);
   double cM = iClose(s.name, InpConfirmTF, 1);
   if(cH <= 0 || cM <= 0) return(0);

   bool h1Price = (dir > 0) ? (cH > h1a) : (cH < h1a);
   bool h1Slope = (dir > 0) ? (h1a > h1b) : (h1a < h1b);

   if(InpHardRegimeGate) {
      if(InpUseADXFilter && adx < InpADXMin * InpHardADXFloorFrac) return(0);
      if(InpUseERFilter && er < InpMinER * InpHardERFloorFrac) return(0);
      if(InpUseHigherTFFilter && !h1Price && !h1Slope) return(0);
   }

   double score = 0.0;

   bool localStack = (dir > 0) ? (emaS > emaT) : (emaS < emaT);
   double sep = MathAbs(emaF - emaS) / atr;
   if(!InpUseEMASepFilter) score += 12.0;
   else {
      if(localStack) score += 7.0;
      if(sep >= InpMinEMASepATR) score += 5.0;
      else if(sep >= InpMinEMASepATR * 0.50) score += 2.0;
   }
   if(!InpUseHigherTFFilter) score += 8.0;
   else {
      if(h1Price) score += 4.0;
      if(h1Slope) score += 4.0;
   }
   if(!InpUseConfirmTFFilter) score += 5.0;
   else if((dir > 0) ? (cM > m15) : (cM < m15)) score += 5.0;

   if(!InpUseADXFilter) score += 12.0;
   else {
      if(adx >= InpADXMin) score += 5.0;
      else if(adx >= InpADXMin * 0.80) score += 2.0;
      if(InpMinADXRise <= -99.0) score += 3.0;
      else if(adx - adx3 >= InpMinADXRise) score += 3.0;
      bool diAlign = (dir > 0) ? (diPlus > diMinus) : (diMinus > diPlus);
      if(diAlign) score += 4.0;
   }
   if(!InpUseERFilter) score += 8.0;
   else {
      if(er >= InpStrongER) score += 8.0;
      else if(er >= InpMinER) score += 5.0;
      else if(er >= InpMinER * 0.70) score += 2.0;
   }

   double emaDist = MathAbs(c - emaF) / atr;
   double closeLoc = (c - l) / range;
   double bodyRatio = MathAbs(c - o) / range;
   bool candleDir = (dir > 0) ? (c > o) : (c < o);

   double pullPts = 0.0;
   if(InpUsePullbackSetup) {
      double rsiExtreme = (dir > 0) ? MathMin(rsi[1], MathMin(rsi[2], rsi[3]))
                                     : MathMax(rsi[1], MathMax(rsi[2], rsi[3]));
      bool rsiRecover = (dir > 0) ? (rsi[0] > rsi[1]) : (rsi[0] < rsi[1]);
      bool rsiPull = (dir > 0) ? (rsiExtreme <= InpRSIPullBuy) : (rsiExtreme >= InpRSIPullSell);
      bool reclaim = (dir > 0) ? (c > emaF && candleDir) : (c < emaF && candleDir);
      if(!InpUseRSIPullback) pullPts += 18.0;
      else {
         if(rsiPull) pullPts += 12.0;
         else if((dir > 0 && rsi[0] < 50.0) || (dir < 0 && rsi[0] > 50.0)) pullPts += 5.0;
         if(rsiRecover) pullPts += 6.0;
      }
      if(reclaim) pullPts += 6.0;
      if(emaDist <= InpMaxExtensionATR * 0.60) pullPts += 6.0;
      else if(emaDist <= InpMaxExtensionATR) pullPts += 3.0;
      pullPts = MathMin(30.0, pullPts);
   }

   double brkPts = 0.0;
   if(InpUseBreakoutSetup) {
      int nStruct = MathMax(3, InpScoreStructureBars);
      MqlRates sr[];
      ArraySetAsSeries(sr, true);
      if(CopyRates(s.name, InpEntryTF, 1, nStruct + 1, sr) == nStruct + 1) {
         double prevHigh = sr[1].high, prevLow = sr[1].low;
         for(int k = 2; k <= nStruct; k++) {
            prevHigh = MathMax(prevHigh, sr[k].high);
            prevLow  = MathMin(prevLow,  sr[k].low);
         }
         bool bos = (dir > 0) ? (c > prevHigh) : (c < prevLow);
         bool dirClose = (dir > 0) ? (closeLoc >= 0.70) : (closeLoc <= 0.30);
         bool midClose = (dir > 0) ? (closeLoc >= 0.55) : (closeLoc <= 0.45);
         if(bos) brkPts += 14.0;
         if(dirClose) brkPts += 6.0;
         else if(midClose) brkPts += 3.0;
         if(bodyRatio >= 0.50) brkPts += 4.0;
         else if(bodyRatio >= InpMinBodyRatio) brkPts += 2.0;
         int vCount = MathMax(5, InpScoreVolumeLookback);
         MqlRates vr[];
         ArraySetAsSeries(vr, true);
         double relVol = 0.0;
         if(CopyRates(s.name, InpEntryTF, 1, vCount + 1, vr) == vCount + 1) {
            double avgVol = 0.0;
            for(int k = 1; k <= vCount; k++) avgVol += (double)vr[k].tick_volume;
            avgVol /= vCount;
            if(avgVol > 0) relVol = (double)vr[0].tick_volume / avgVol;
         }
         if(relVol <= 0) brkPts += 3.0;
         else if(relVol >= 1.20) brkPts += 6.0;
         else if(relVol >= 0.90) brkPts += 3.0;
         if(emaDist > InpMaxExtensionATR) brkPts *= 0.5;
         brkPts = MathMin(30.0, brkPts);
         if(!bos) brkPts = 0.0;
      }
   }
   double trigger = MathMax(pullPts, brkPts);
   g_setupTag = (pullPts >= brkPts) ? "PULLBACK" : "BREAKOUT";
   if(trigger < InpMinSetupPoints) return(0);
   score += trigger;

   if(!InpUseCandleFilter) score += 10.0;
   else {
      if(candleDir) score += 4.0;
      if(bodyRatio >= InpMinBodyRatio) score += 4.0;
      else if(bodyRatio >= InpMinBodyRatio * 0.70) score += 2.0;
      if(range <= InpMaxSignalCandleATR * atr) score += 2.0;
   }

   if(!InpUseATRRatioFilter) score += 10.0;
   else if(ratio >= 0.75 && ratio <= InpHighVolRatio) score += 10.0;
   else if(ratio < 0.75) score += 6.0;
   else if(ratio <= InpMaxATRRatio) score += 4.0;

   MqlTick tk;
   if(SymbolInfoTick(s.name, tk) && tk.ask > tk.bid) {
      double spr = (tk.ask - tk.bid) / atr;
      if(spr <= 0.05) score += 5.0;
      else if(spr <= 0.10) score += 3.0;
      else score += 1.0;
   } else score += 2.0;

   score = MathMax(0.0, MathMin(100.0, score));

   scoreThreshold = InpScoreBaseThreshold;
   bool strongRegime = (adx >= InpADXStrong && er >= InpStrongER &&
                        ratio >= 0.75 && ratio <= InpHighVolRatio);
   bool weakRegime = (adx < InpADXMin || er < InpMinER);
   if(strongRegime) scoreThreshold -= InpScoreStrongDiscount;
   if(weakRegime) scoreThreshold += InpScoreChopPenalty;
   if(ratio > InpHighVolRatio) scoreThreshold += 3.0;
   scoreThreshold = MathMax(55.0, MathMin(92.0, scoreThreshold));

   signalScore = score;
   if(InpUseAdaptiveScoring) {
      if(score < scoreThreshold) return(0);
      double quality = (score - scoreThreshold) / MathMax(1.0, 100.0 - scoreThreshold);
      riskMult = 0.55 + 0.45 * MathMax(0.0, MathMin(1.0, quality));
   } else {
      if(score < InpScoreBaseThreshold) return(0);
      riskMult = (adx >= InpADXStrong && er >= InpStrongER) ? InpRiskMultStrong : InpRiskMultNormal;
   }
   if(ratio >= InpHighVolRatio) riskMult *= InpHighVolRiskCut;
   riskMult = MathMax(0.25, MathMin(1.0, riskMult));
   return(dir);
}

int EvaluateMeanReversionSignal(SymState &s, double &atr, double &adx, double &riskMult,
                                double &signalScore, double &scoreThreshold) {
   signalScore = 0.0;
   scoreThreshold = InpMRScoreThreshold;
   g_mrTarget = 0.0;
   if(!InpUseMeanReversion) return(0);
   if(Bars(s.name, InpEntryTF) < InpMRBandsPeriod + InpERLookback + 10) return(0);

   if(!Val(s.hAtr, 1, atr) || !Val(s.hAdx, 1, adx) || atr <= 0.0) return(0);
   if(adx > InpMRADXMax) return(0);
   double er = Efficiency(s.name, InpEntryTF, InpERLookback);
   g_lastER = er;
   double atrRef = 0.0;
   g_lastRatio = (Val(s.hAtrRef, 1, atrRef) && atrRef > 0.0) ? atr / atrRef : 1.0;
   if(er > InpMRERMax) return(0);

   if(InpMRH1FlatATR > 0.0) {
      double h1a, h1b;
      if(!Val(s.hH1, 1, h1a) || !Val(s.hH1, 4, h1b)) return(0);
      if(MathAbs(h1a - h1b) > InpMRH1FlatATR * atr) return(0);
   }

   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(s.name, InpEntryTF, 2, InpMRBandsPeriod, closes) != InpMRBandsPeriod) return(0);
   double mean = 0.0;
   for(int i = 0; i < InpMRBandsPeriod; i++) mean += closes[i];
   mean /= (double)InpMRBandsPeriod;
   double variance = 0.0;
   for(int i = 0; i < InpMRBandsPeriod; i++) {
      double d = closes[i] - mean;
      variance += d * d;
   }
   variance /= (double)InpMRBandsPeriod;
   double sd = MathSqrt(variance);
   if(sd <= 0.0) return(0);
   double upper = mean + InpMRBandsDeviation * sd;
   double lower = mean - InpMRBandsDeviation * sd;
   if((upper - lower) < InpMRMinBandWidthATR * atr) return(0);

   // Confirm a genuine participation expansion on the closed signal bar.
   // Baseline uses the preceding closed bars only (no current/future data).
   int vCount = MathMax(5, InpScoreVolumeLookback);
   MqlRates mrVol[];
   ArraySetAsSeries(mrVol, true);
   if(CopyRates(s.name, InpEntryTF, 1, vCount + 1, mrVol) != vCount + 1) return(0);
   double avgTickVol = 0.0;
   for(int vi = 1; vi <= vCount; vi++) avgTickVol += (double)mrVol[vi].tick_volume;
   avgTickVol /= (double)vCount;
   if(avgTickVol <= 0.0 || (double)mrVol[0].tick_volume < InpMRVolSpikeMult * avgTickVol) return(0);

   double rsi[];
   if(!Buf(s.hRsi, 0, 1, 2, rsi)) return(0);
   double o = iOpen(s.name, InpEntryTF, 1);
   double h = iHigh(s.name, InpEntryTF, 1);
   double l = iLow(s.name, InpEntryTF, 1);
   double c = iClose(s.name, InpEntryTF, 1);
   if(o <= 0 || h <= 0 || l <= 0 || c <= 0 || h <= l) return(0);

   bool buySignal  = (l < lower && c > lower && c > o && rsi[0] <= InpMRRSIBuy);
   bool sellSignal = (h > upper && c < upper && c < o && rsi[0] >= InpMRRSISell);
   if(!buySignal && !sellSignal) return(0);

   double rng = h - l;
   double closeLoc = (c - l) / rng;
   double bodyRatio = MathAbs(c - o) / rng;
   double loc = buySignal ? closeLoc : (1.0 - closeLoc);
   double pen = buySignal ? (lower - l) / atr : (h - upper) / atr;
   double rsiDepth = buySignal ? (InpMRRSIBuy - rsi[0]) : (rsi[0] - InpMRRSISell);

   double score = 40.0;
   score += 15.0 * MathMax(0.0, MathMin(1.0, (loc - 0.50) / 0.35));
   score += 10.0 * MathMax(0.0, MathMin(1.0, bodyRatio / 0.60));
   score += 10.0 * MathMax(0.0, MathMin(1.0, 1.0 - adx / MathMax(1e-9, InpMRADXMax)));
   score += 10.0 * MathMax(0.0, MathMin(1.0, 1.0 - er / MathMax(1e-9, InpMRERMax)));
   score += 10.0 * MathMax(0.0, MathMin(1.0, pen / 0.30));
   score += 5.0 * MathMax(0.0, MathMin(1.0, rsiDepth / 10.0));
   score = MathMin(100.0, score);

   scoreThreshold = InpMRScoreThreshold;
   signalScore = score;
   g_setupTag = "MEAN_REVERSION";
   if(score < scoreThreshold) return(0);

   double quality = (score - scoreThreshold) / MathMax(1.0, 100.0 - scoreThreshold);
   riskMult = MathMax(0.20, MathMin(1.0, InpMRRiskMult * (0.70 + 0.30 * MathMax(0.0, MathMin(1.0, quality)))));
   // Optional farther target: opposite Bollinger band instead of the midline.
   g_mrTarget = InpMRUseOppositeBand ? (buySignal ? upper : lower) : mean;
   return(buySignal ? 1 : -1);
}

int EvaluateSignal(SymState &s, double &atr, double &adx, double &riskMult,
                   double &signalScore, double &scoreThreshold) {
   int dir = EvaluateTrendSignal(s, atr, adx, riskMult, signalScore, scoreThreshold);
   if(dir != 0) return(dir);
   double trendScore = signalScore, trendThr = scoreThreshold;
   string trendTag = g_setupTag;
   g_setupTag = "";
   dir = EvaluateMeanReversionSignal(s, atr, adx, riskMult, signalScore, scoreThreshold);
   if(dir != 0) return(dir);
   if(trendScore > 0.0) { signalScore = trendScore; scoreThreshold = trendThr; g_setupTag = trendTag; }
   else if(signalScore <= 0.0) { signalScore = 0.0; g_setupTag = "NO_SETUP"; }
   return(0);
}

bool BuildStops(SymState &s, const int dir, const double atr, const double rr, const double entry,
                double &sl, double &tp, double &dist) {
   double buf = InpStructBufATR * atr;
   int idx;
   if(dir > 0) {
      idx = iLowest(s.name, InpEntryTF, MODE_LOW, InpStructBars, 1);
      if(idx < 0) return(false);
      sl = iLow(s.name, InpEntryTF, idx) - buf;
      dist = entry - sl;
   } else {
      idx = iHighest(s.name, InpEntryTF, MODE_HIGH, InpStructBars, 1);
      if(idx < 0) return(false);
      sl = iHigh(s.name, InpEntryTF, idx) + buf;
      dist = sl - entry;
   }
   if(dist > InpMaxStructATR * atr) return(false);
   double minD = InpMinStructATR * atr;
   double stopsLvl = (double)SymbolInfoInteger(s.name, SYMBOL_TRADE_STOPS_LEVEL) * s.point;
   MqlTick stopTick;
   if(!SymbolInfoTick(s.name, stopTick) || stopTick.bid <= 0 || stopTick.ask <= 0) return(false);
   double liveSpread = stopTick.ask - stopTick.bid;
   minD = MathMax(minD, stopsLvl + liveSpread + InpExtraStopBufPts * s.point);
   if(dist < minD) dist = minD;
   sl = (dir > 0) ? entry - dist : entry + dist;
   tp = (dir > 0) ? entry + rr * dist : entry - rr * dist;
   sl = NormalizePriceTick(s.name, sl);
   tp = NormalizePriceTick(s.name, tp);
   dist = MathAbs(entry - sl);
   if(dist <= 0 || dist > InpMaxStructATR * atr + s.point) return(false);
   MqlTick verify;
   if(!SymbolInfoTick(s.name, verify) || verify.bid<=0 || verify.ask<=0) return(false);
   double minBroker=(double)SymbolInfoInteger(s.name,SYMBOL_TRADE_STOPS_LEVEL)*s.point;
   if(dir>0 && sl>=verify.bid-minBroker-s.point) return(false);
   if(dir<0 && sl<=verify.ask+minBroker+s.point) return(false);
   return(true);
}

bool PostFillRiskOK(const string sym, const bool buy, const double open,
                    const double sl, const double tp, const double vol,
                    const ulong ticket, string &reason) {
   reason = "";
   if(ticket == 0 || open <= 0 || vol <= 0) {
      reason = "position ou volume invalide";
      return(false);
   }
   if(sl <= 0 || (buy && sl >= open) || (!buy && sl <= open)) {
      reason = "SL absent ou du mauvais côté";
      return(false);
   }
   if(tp > 0 && ((buy && tp <= open) || (!buy && tp >= open))) {
      reason = "TP du mauvais côté";
      return(false);
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0) {
      reason = "equity invalide";
      return(false);
   }
   double risk = PosRiskMoney(sym, buy, open, sl, vol);
   if(risk <= 0 || risk > eq * EffectiveRiskPerTradePct() / 100.0 + 0.01) {
      reason = "risque individuel hors limite";
      return(false);
   }
   if(OpenRiskTotal() > eq * EffectiveTotalRiskPct() / 100.0 + 0.01) {
      reason = "risque portefeuille hors limite";
      return(false);
   }

   int si = SymIndex(sym);
   if(si >= 0 && !ExposureOK(g_s[si], buy ? 1 : -1, 0.0)) {
      reason = "exposition devise hors limite";
      return(false);
   }
   return(true);
}

//======================== EXÉCUTION ========================
void NoteBadFill() {
   g_badFills++;
   if(InpMaxBadFills > 0 && g_badFills >= InpMaxBadFills) {
      g_pauseUntil = TimeCurrent() + InpPauseMinutes * 60;
      g_badFills = 0;
      Log("Pause " + IntegerToString(InpPauseMinutes) + " min : fills rejetés en série");
   }
}

bool CloseRejected(const ulong tk, const string reason) {
   NoteBadFill();
   if(!ClosePos(tk, "fill rejeté: " + reason)) {
      Halt(HALT_CRITICAL);
      Print("CRITIQUE BLACKHIPPO: fermeture de sécurité échouée ticket=", tk, " motif=", reason,
            " | entrées désactivées, intervention requise.");
      return(false);
   }
   return(true);
}

bool OpenTrade(SymState &s, const int dir, const double lots, const double sl, const double tp,
               const double atr, const double adx, const double plannedRisk, const string why) {
   if(s.lockUntil > TimeCurrent()) return(false);
   if(s.point <= 0 || atr <= 0 || lots <= 0 || sl <= 0 || tp <= 0) return(false);
   double devRaw = (double)InpBaseDeviation + (atr / s.point) * InpDevATRMult;
   int dev = (int)MathMax((double)InpBaseDeviation, MathMin((double)InpMaxDeviation, devRaw));
   g_trade.SetDeviationInPoints(dev);
   g_trade.SetTypeFillingBySymbol(s.name);

   bool ok = false;
   bool placedUnconfirmed = false;
   double reqPrice = 0;
   uint rc = 0;
   for(int a = 0; a < InpMaxRetries; a++) {
      if(!TradingAllowed()) { Sleep(InpRetryDelayMs); continue; }
      MqlTick t;
      if(!SymbolInfoTick(s.name, t)) { Sleep(InpRetryDelayMs); continue; }
      reqPrice = (dir > 0) ? t.ask : t.bid;
      ok = (dir > 0) ? g_trade.Buy(lots, s.name, reqPrice, sl, tp, "BLACKHIPPO")
                     : g_trade.Sell(lots, s.name, reqPrice, sl, tp, "BLACKHIPPO");
      rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL)) break;
      if(rc == TRADE_RETCODE_PLACED) {
         placedUnconfirmed = true;
         ok = true;
         break;
      }
      ok = false;
      if(rc == TRADE_RETCODE_TIMEOUT || rc == TRADE_RETCODE_CONNECTION) {
         s.lockUntil = TimeCurrent() + InpUncertainLockMin * 60;
         GlobalVariableSet(K("lk_" + s.name), (double)s.lockUntil);
         Print("ALERTE BLACKHIPPO: résultat d'ordre incertain sur ", s.name, " (retcode ", rc,
               "). Symbole verrouillé ", InpUncertainLockMin, " min; vérifier les positions.");
         return(false);
      }
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
         rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_TOO_MANY_REQUESTS) { Sleep(InpRetryDelayMs); continue; }
      break;
   }
   if(!ok) { Log("Ordre refusé " + s.name + " retcode=" + IntegerToString((int)rc) + " " + g_trade.ResultRetcodeDescription()); return(false); }

   ulong tk = 0; ulong pid = 0;
   double open = 0, psl = 0, vol = 0;
   ulong deal = g_trade.ResultDeal();
   if(placedUnconfirmed || deal == 0 || !HistoryDealSelect(deal)) {
      s.lockUntil = TimeCurrent() + InpUncertainLockMin * 60;
      GlobalVariableSet(K("lk_" + s.name), (double)s.lockUntil);
      Print("ALERTE BLACKHIPPO: ordre accepté sans deal confirmé sur ", s.name,
            "; symbole verrouillé, aucune nouvelle entrée.");
      return(false);
   }
   pid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(pid > 0) {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong x = PositionGetTicket(i);
         if(x == 0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) != pid) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagic ||
            PositionGetString(POSITION_SYMBOL) != s.name) continue;
         tk = x;
         open = PositionGetDouble(POSITION_PRICE_OPEN);
         psl = PositionGetDouble(POSITION_SL);
         vol = PositionGetDouble(POSITION_VOLUME);
         break;
      }
   }
   if(tk == 0) {
      s.lockUntil = TimeCurrent() + InpUncertainLockMin * 60;
      GlobalVariableSet(K("lk_" + s.name), (double)s.lockUntil);
      Print("ALERTE BLACKHIPPO: deal exécuté mais position non réconciliée sur ", s.name,
            "; symbole verrouillé, vérification requise.");
      return(false);
   }

   if(psl <= 0 || (dir > 0 && psl >= open) || (dir < 0 && psl <= open)) {
      CloseRejected(tk, "SL absent ou invalide");
      return(false);
   }
   if(MathAbs(open - reqPrice) > InpMaxFillDevATR * atr) {
      CloseRejected(tk, "déviation de prix excessive");
      return(false);
   }
   double actualRisk = PosRiskMoney(s.name, dir > 0, open, psl, vol);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double cap = MathMin(eq * EffectiveRiskPerTradePct() / 100.0, plannedRisk * (1.0 + InpPostFillRiskTolPct / 100.0));
   string postFillReason;
   bool commonGuardsOK = PostFillRiskOK(s.name, dir > 0, open, psl, tp, vol, tk, postFillReason);
   if(!commonGuardsOK || actualRisk > cap + 0.01) {
      CloseRejected(tk, "contrôle post-exécution: " + postFillReason +
                    " (risque=" + DoubleToString(actualRisk, 2) + ")");
      return(false);
   }

   GlobalVariableSet(KP("R0", pid), MathAbs(open - psl));
   GlobalVariableSet(KP("RM", pid), actualRisk);
   GlobalVariableSet(KP("AS", pid), (adx >= InpADXStrong) ? 1.0 : 0.0);
   GlobalVariableSet(KP("ST", pid), (g_setupTag == "MEAN_REVERSION") ? 2.0 : ((g_setupTag == "BREAKOUT") ? 1.0 : 0.0));
   g_tradesToday++;
   s.tradesToday++;
   s.lastEntryBar = iTime(s.name, InpEntryTF, 0);
   SaveState();
   Csv("OPEN", s.name, vol, open, psl, tp, 0, 0, why + "|pid=" + IntegerToString((long)pid));
   Log("OPEN " + s.name + " " + (dir > 0 ? "BUY" : "SELL") + " lots=" + DoubleToString(vol, 2) +
       " risk=" + DoubleToString(actualRisk, 2) + " " + why);
   return(true);
}

//======================== ENTRÉES ========================
string RejName(const int i) {
   switch(i) {
      case REJ_SPREAD:    return("spread");
      case REJ_CALENDAR:  return("calendrier");
      case REJ_SAMEDIR:   return("même_direction");
      case REJ_STOPS:     return("stops/cible");
      case REJ_COST:      return("coût");
      case REJ_LOTS:      return("lots/marge");
      case REJ_PORTFOLIO: return("portefeuille");
      case REJ_EXPOSURE:  return("exposition_devise");
      case REJ_STALE:     return("signal_périmé/cotation");
      case REJ_CORR:      return("corrélation");
   }
   return("?");
}

void Rej(const int code) { if(code >= 0 && code < REJ_N) g_rej[code]++; }

void RejOnce(SymState &s, const int code) {
   if(s.rejBar == s.lastBar) return;
   s.rejBar = s.lastBar;
   Rej(code);
}

bool HasUnprotectedPosition() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetDouble(POSITION_SL) <= 0) return(true);
   }
   return(false);
}

void LogRejSummary() {
   if(TimeCurrent() - g_lastRejLog < 3600) return;
   g_lastRejLog = TimeCurrent();
   string msg = "";
   int tot = 0;
   for(int i = 0; i < REJ_N; i++) {
      if(g_rej[i] <= 0) continue;
      msg += RejName(i) + "=" + IntegerToString(g_rej[i]) + " ";
      tot += g_rej[i];
      g_rej[i] = 0;
   }
   if(tot > 0) Log("REJETS (1h) " + msg);
   if(InpPortfolioAllPositions && !MQLInfoInteger(MQL_TESTER) && HasUnprotectedPosition())
      Print("ALERTE BLACKHIPPO: position SANS SL sur le compte : risque portefeuille = equity, toutes les entrées sont bloquées.");
}

void SigCsv(const string sym, const string tag, const int dir, const double score, const double thr,
            const double adx, const double er, const double atr) {
   if(!InpLogSignals || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   int h = FileOpen(InpSignalsFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0)
      FileWriteString(h, "time,symbol,setup,dir,score,threshold,accepted,adx,er,atr_pts,ratio\r\n");
   FileSeek(h, 0, SEEK_END);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   string line = CsvField(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)) + "," + CsvField(sym) + "," +
                 CsvField(tag) + "," + IntegerToString(dir) + "," + DoubleToString(score, 1) + "," +
                 DoubleToString(thr, 1) + "," + (dir != 0 ? "1" : "0") + "," + DoubleToString(adx, 1) + "," +
                 DoubleToString(er, 3) + "," + DoubleToString(pt > 0 ? atr / pt : 0.0, 1) + "," +
                 DoubleToString(g_lastRatio, 2) + "\r\n";
   FileWriteString(h, line);
   FileClose(h);
}

void EvaluateEntry(SymState &s) {
   datetime bt = iTime(s.name, InpEntryTF, 0);
   if(bt == 0) return;
   if(bt != s.lastBar) { s.lastBar = bt; s.done = false; }
   if(s.done) return;
   if(TimeCurrent() - bt > InpEntryWindowSec) { s.done = true; return; }

   if(s.lockUntil > TimeCurrent()) return;
   if(InpCooldownBars > 0 && s.lastEntryBar > 0 &&
      (bt - s.lastEntryBar) < InpCooldownBars * PeriodSeconds(InpEntryTF)) { s.done = true; return; }
   int exitBars = s.lastExitLoss ? InpCooldownLossBars : InpCooldownExitBars;
   if(exitBars > 0 && s.lastExit > 0 &&
      (TimeCurrent() - s.lastExit) < (datetime)(exitBars * PeriodSeconds(InpEntryTF))) { s.done = true; return; }
   if(IsHedgingAccount()) {
      if(HasPosition(s.name)) { s.done = true; return; }
   } else {
      if(HasAnyPositionOnSymbol(s.name)) { s.done = true; return; }
   }
   if(CountOpen() >= EffectiveMaxOpenTrades()) return;
   if(EffectiveMaxTradesPerDay() > 0 && g_tradesToday >= EffectiveMaxTradesPerDay()) return;
   if(EffectiveMaxTradesPerSymbol() > 0 && s.tradesToday >= EffectiveMaxTradesPerSymbol()) return;
   if(!CanTradeDirection(s.name, 1) && !CanTradeDirection(s.name, -1)) return;

   MqlTick t;
   if(!SymbolInfoTick(s.name, t) || t.ask <= 0 || t.bid <= 0) return;
   long quoteAge = (long)(TimeCurrent() - t.time);
   if(quoteAge < 0 || quoteAge > InpMaxQuoteAgeSec) { RejOnce(s, REJ_STALE); return; }
   double spread = t.ask - t.bid;
   double atr0;
   if(!Val(s.hAtr, 1, atr0) || atr0 <= 0) return;
   double spreadPts = spread / s.point;
   if(spreadPts > InpMaxSpreadPoints || spread > InpMaxSpreadATRFrac * atr0 ||
      !SpreadPercentileAllowed(s.name, spreadPts)) { RejOnce(s, REJ_SPREAD); return; }
   if(CalendarBlocked(s)) { RejOnce(s, REJ_CALENDAR); return; }

   double atr = 0, adx = 0, rm = 1.0, signalScore = 0.0, scoreThreshold = InpScoreBaseThreshold;
   int dir = EvaluateSignal(s, atr, adx, rm, signalScore, scoreThreshold);
   s.done = true;
   if(signalScore > 0.0 || dir != 0) SigCsv(s.name, g_setupTag, dir, signalScore, scoreThreshold, adx, g_lastER, atr);
   if(dir == 0) {
      if(InpLogSignalScore && signalScore > 0)
         Log("SIGNAL_REJECT " + s.name + " " + g_setupTag + " score=" + DoubleToString(signalScore, 1) +
             " threshold=" + DoubleToString(scoreThreshold, 1));
      return;
   }
   // exiger une marge de score minimale (qualité d'edge)
   if(signalScore - scoreThreshold < InpMinScoreMargin) {
      if(InpLogSignalScore)
         Log("SIGNAL_MARGIN " + s.name + " " + g_setupTag + " margin=" +
             DoubleToString(signalScore - scoreThreshold, 1) + " < " + DoubleToString(InpMinScoreMargin, 1));
      return;
   }
   if(CountDir(dir) >= EffectiveMaxSameDirection()) { Rej(REJ_SAMEDIR); return; }

   int n = ArraySize(g_cand);
   ArrayResize(g_cand, n + 1);
   g_cand[n].si = SymIndex(s.name);
   g_cand[n].dir = dir;
   g_cand[n].score = signalScore;
   g_cand[n].thr = scoreThreshold;
   g_cand[n].rm = rm;
   g_cand[n].adx = adx;
   g_cand[n].er = g_lastER;
   g_cand[n].atrRatio = g_lastRatio;
   g_cand[n].atr = atr;
   g_cand[n].mrTarget = g_mrTarget;
   g_cand[n].tag = g_setupTag;
   g_cand[n].bar = bt;
   if(n == 0) g_candFirst = TimeCurrent();
}

void ExecuteOn(SymState &s, const Cand &c);

bool QueuePullback(SymState &s, const Cand &c, const double price, const double atr) {
   if(!InpUsePullbackRecovery || atr <= 0.0 || price <= 0.0) return(false);
   double signalClose = iClose(s.name, InpEntryTF, 1);
   if(signalClose <= 0.0) return(false);
   double distanceATR = MathAbs(price-signalClose)/atr;
   if(distanceATR > InpPullbackWatchMaxATR) return(false);
   // Un seul signal en attente par symbole et par bougie.
   for(int i=ArraySize(g_pullbacks)-1; i>=0; i--) {
      if(g_pullbacks[i].c.si == c.si && g_pullbacks[i].c.bar == c.bar) return(true);
   }
   int n=ArraySize(g_pullbacks);
   ArrayResize(g_pullbacks,n+1);
   g_pullbacks[n].c=c;
   g_pullbacks[n].extreme=price;
   g_pullbacks[n].lastPrice=price;
   g_pullbacks[n].created=TimeCurrent();
   g_pullbacks[n].retraced=false;
   if(InpLogSignalScore) Log("PULLBACK_WAIT " + s.name + " dir=" + (c.dir>0?"BUY":"SELL") +
      " distanceATR=" + DoubleToString(distanceATR,2));
   return(true);
}

void RemovePullback(const int idx) {
   int n = ArraySize(g_pullbacks);
   if(idx < 0 || idx >= n) return;
   for(int j = idx; j < n - 1; j++) g_pullbacks[j] = g_pullbacks[j + 1];
   ArrayResize(g_pullbacks, n - 1);
}

void ProcessPullbackRecoveries() {
   for(int i=ArraySize(g_pullbacks)-1; i>=0; i--) {
      Cand c=g_pullbacks[i].c;
      if(c.si<0 || c.si>=g_n || TimeCurrent()-c.bar>InpEntryWindowSec ||
         TimeCurrent()-g_pullbacks[i].created>InpEntryWindowSec) {
         RemovePullback(i);
         continue;
      }
      MqlTick tick;
      if(!SymbolInfoTick(g_s[c.si].name,tick)) continue;
      double price=(c.dir>0)?tick.ask:tick.bid;
      if(price<=0.0 || c.atr<=0.0) continue;
      if(c.dir>0) {
         if(price>g_pullbacks[i].extreme) g_pullbacks[i].extreme=price;
         if(g_pullbacks[i].extreme-price>=InpPullbackMinRetraceATR*c.atr) g_pullbacks[i].retraced=true;
      } else {
         if(price<g_pullbacks[i].extreme) g_pullbacks[i].extreme=price;
         if(price-g_pullbacks[i].extreme>=InpPullbackMinRetraceATR*c.atr) g_pullbacks[i].retraced=true;
      }
      double close=iClose(g_s[c.si].name,InpEntryTF,1);
      bool nearSignal=(close>0.0 && MathAbs(price-close)/c.atr<=InpMaxEntryDistanceATR);
      bool resumed=(c.dir>0)?(price>g_pullbacks[i].lastPrice):(price<g_pullbacks[i].lastPrice);
      g_pullbacks[i].lastPrice=price;
      if(g_pullbacks[i].retraced && nearSignal && resumed) {
         RemovePullback(i);
         if(InpLogSignalScore) Log("PULLBACK_RECLAIM " + g_s[c.si].name + " signal=" + TimeToString(c.bar));
         ExecuteOn(g_s[c.si],c);
      }
   }
}

void ExecuteOn(SymState &s, const Cand &c) {
   const int dir = c.dir;
   if(!CanTradeDirection(s.name, dir)) { Rej(REJ_PORTFOLIO); return; }
   if(s.lockUntil > TimeCurrent()) return;
   if(CountOpen() >= EffectiveMaxOpenTrades()) { Rej(REJ_PORTFOLIO); return; }
   if(EffectiveMaxTradesPerDay() > 0 && g_tradesToday >= EffectiveMaxTradesPerDay()) return;
   if(EffectiveMaxTradesPerSymbol() > 0 && s.tradesToday >= EffectiveMaxTradesPerSymbol()) return;
   if(IsHedgingAccount()) { if(HasPosition(s.name)) return; }
   else if(HasAnyPositionOnSymbol(s.name)) return;
   if(CountDir(dir) >= EffectiveMaxSameDirection()) { Rej(REJ_SAMEDIR); return; }
   // Filtre de corrélation – évite d'empiler du risque quasi-identique
   if(!CorrelationOK(s.name, dir)) {
      Rej(REJ_CORR);
      if(InpLogSignalScore) Log("CORR_REJECT " + s.name + " dir=" + (dir>0?"BUY":"SELL"));
      return;
   }

   MqlTick t;
   if(!SymbolInfoTick(s.name, t) || t.ask <= 0 || t.bid <= 0) { Rej(REJ_STALE); return; }
   if(TimeCurrent() - t.time > InpMaxQuoteAgeSec) { Rej(REJ_STALE); return; }
   double spread = t.ask - t.bid;
   double spreadPts = spread / s.point;
   if(spreadPts > InpMaxSpreadPoints || spread > InpMaxSpreadATRFrac * c.atr ||
      !SpreadPercentileAllowed(s.name, spreadPts)) { Rej(REJ_SPREAD); return; }

   double atr = c.atr, adx = c.adx, rm = c.rm;
   double acceptedScore = c.score, acceptedThreshold = c.thr;
   double acceptedER = c.er, acceptedATRRatio = c.atrRatio;
   bool isMR = (c.tag == "MEAN_REVERSION");
   double mrTarget = c.mrTarget;
   if(InpRevalidateCandidate) {
      // The setup must still be valid on the same signal bar immediately before execution.
      if(iTime(s.name, InpEntryTF, 0) != c.bar) { Rej(REJ_STALE); return; }
      double freshATR=0.0, freshADX=0.0, freshRiskMult=1.0, freshScore=0.0, freshThreshold=InpScoreBaseThreshold;
      int freshDir=EvaluateSignal(s, freshATR, freshADX, freshRiskMult, freshScore, freshThreshold);
      string freshTag=g_setupTag;
      double freshMRTarget=g_mrTarget;
      if(freshDir != dir || freshTag != c.tag || freshATR <= 0.0 ||
         freshScore < freshThreshold + InpMinScoreMargin) {
         Rej(REJ_STALE);
         if(InpLogSignalScore) Log("CANDIDATE_INVALIDATED " + s.name + " setup=" + c.tag + " fresh=" + freshTag);
         return;
      }
      if(MathAbs(freshATR-c.atr) > c.atr*InpMaxCandidateATRChange) { Rej(REJ_STALE); return; }
      atr=freshATR; adx=freshADX; rm=freshRiskMult;
      acceptedScore=freshScore; acceptedThreshold=freshThreshold;
      acceptedER=g_lastER; acceptedATRRatio=g_lastRatio;
      mrTarget=freshMRTarget;
      isMR=(freshTag=="MEAN_REVERSION");
   }
   double entry = (dir > 0) ? t.ask : t.bid;
   double signalClose=iClose(s.name, InpEntryTF, 1);
   if(signalClose<=0.0 || atr<=0.0) { Rej(REJ_STALE); return; }

   // Anti-poursuite adaptatif : l'assouplissement dépend simultanément de l'ADX,
   // de l'efficacité directionnelle et de la marge du score. Aucun critère seul
   // ne peut autoriser une entrée très étendue.
   double distanceATR = MathAbs(entry-signalClose)/atr;
   double maxDistanceATR = InpMaxEntryDistanceATR;
   double chaseRiskFactor = 1.0;
   if(InpUseAdaptiveAntiChase) {
      double adxQ = (InpAdaptiveMinADX > 0.0 ? MathMax(0.0, MathMin(1.0, (adx-InpAdaptiveMinADX)/10.0)) : 0.0);
      double erQ = (InpAdaptiveMinER > 0.0 ? MathMax(0.0, MathMin(1.0, (acceptedER-InpAdaptiveMinER)/0.20)) : 0.0);
      double margin = acceptedScore-acceptedThreshold;
      double scoreQ = (InpAdaptiveMinScoreMargin > 0.0 ? MathMax(0.0, MathMin(1.0, margin/InpAdaptiveMinScoreMargin)) : 0.0);
      double quality = MathMin(adxQ, MathMin(erQ, scoreQ));
      maxDistanceATR = InpMaxEntryDistanceATR +
                       MathMax(0.0, InpAdaptiveMaxDistanceATR-InpMaxEntryDistanceATR)*quality;
      // Une extension autorisée reste moins bien rémunérée en risque : réduction
      // graduelle du volume au-delà du seuil normal, sans toucher au SL structurel.
      if(distanceATR > InpMaxEntryDistanceATR && InpAdaptiveMaxDistanceATR > InpMaxEntryDistanceATR) {
         double extension = MathMin(1.0, (distanceATR-InpMaxEntryDistanceATR)/
                                    (InpAdaptiveMaxDistanceATR-InpMaxEntryDistanceATR));
         chaseRiskFactor = 1.0 - MathMax(0.0, MathMin(1.0, InpChaseRiskReduction))*extension;
      }
   }
   if(distanceATR > maxDistanceATR) {
      if(QueuePullback(s,c,entry,atr)) return;
      Rej(REJ_STALE);
      if(InpLogSignalScore) Log("ANTI_CHASE_REJECT " + s.name + " distanceATR=" +
         DoubleToString(distanceATR,2) + " max=" + DoubleToString(maxDistanceATR,2));
      return;
   }
   if(InpLogSignalScore && distanceATR > InpMaxEntryDistanceATR)
      Log("ANTI_CHASE_ADAPT " + s.name + " distanceATR=" + DoubleToString(distanceATR,2) +
          " max=" + DoubleToString(maxDistanceATR,2) + " riskFactor=" + DoubleToString(chaseRiskFactor,2));
   double rr = isMR ? InpMRMinRR : ((adx >= InpADXStrong) ? InpRRStrong : InpRRBase);
   double sl, tp, dist;
   if(!BuildStops(s, dir, atr, rr, entry, sl, tp, dist)) { Rej(REJ_STOPS); return; }
   double tpDist = rr * dist;
   if(isMR) {
      double md = (dir > 0) ? (mrTarget - entry) : (entry - mrTarget);
      if(mrTarget <= 0.0 || md < InpMRMinRR * dist) { Rej(REJ_STOPS); return; }
      tp = NormalizePriceTick(s.name, (dir > 0) ? entry + md : entry - md);
      tpDist = MathAbs(tp - entry);
      if(tpDist <= 0.0) { Rej(REJ_STOPS); return; }
   }

   double ts = SymbolInfoDouble(s.name, SYMBOL_TRADE_TICK_SIZE), tv = TickValue(s.name);
   if(ts <= 0 || tv <= 0) return;
   double commPrice = (InpCommissionPerLot > 0) ? InpCommissionPerLot / (tv / ts) : 0.0;
   if((spread + commPrice) / tpDist > (isMR ? InpMRMaxCostToTP : InpMaxCostToTP)) { Rej(REJ_COST); return; }

   double riskMoney;
   double lots = CalcLots(s, dir, entry, dist, rm, adx, acceptedER, acceptedATRRatio, chaseRiskFactor, riskMoney);
   if(lots <= 0) { Rej(REJ_LOTS); return; }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   // Le plafond effectif SAFE doit être identique avant et après exécution.
   if(OpenRiskTotal() + riskMoney > eq * EffectiveTotalRiskPct() / 100.0 + 0.01) { Rej(REJ_PORTFOLIO); return; }
   if(!ExposureOK(s, dir, riskMoney)) { Rej(REJ_EXPOSURE); return; }

   g_setupTag = c.tag;
   g_mrTarget = mrTarget;
   string why = "SETUP=" + c.tag + "|SCORE=" + DoubleToString(acceptedScore, 1) + "/" + DoubleToString(acceptedThreshold, 1) +
                "|ADX=" + DoubleToString(adx, 1) + "|RR=" + DoubleToString(tpDist / dist, 2) + "|rm=" + DoubleToString(rm, 2);
   if(InpLogSignalScore) Log("SIGNAL_ACCEPT " + s.name + " " + c.tag + " dir=" + (dir > 0 ? "BUY" : "SELL") +
                            " score=" + DoubleToString(acceptedScore, 1) + " threshold=" +
                            DoubleToString(acceptedThreshold, 1) + " riskMult=" + DoubleToString(rm, 2));
   OpenTrade(s, dir, lots, sl, tp, atr, adx, riskMoney, why);
}

void ProcessCandidates() {
   int n = ArraySize(g_cand);
   if(n == 0) return;
   if(TimeCurrent() - g_candFirst < InpRankWaitSec) return;
   for(int i = 1; i < n; i++) {
      Cand x;
      x = g_cand[i];
      double kx = x.score - x.thr;
      int j = i - 1;
      while(j >= 0 && (g_cand[j].score - g_cand[j].thr) < kx) { g_cand[j + 1] = g_cand[j]; j--; }
      g_cand[j + 1] = x;
   }
   for(int i = 0; i < n; i++) {
      if(g_cand[i].si < 0 || g_cand[i].si >= g_n) continue;
      if(TimeCurrent() - g_cand[i].bar > InpEntryWindowSec) { Rej(REJ_STALE); continue; }
      ExecuteOn(g_s[g_cand[i].si], g_cand[i]);
   }
   ArrayResize(g_cand, 0);
}

//======================== GESTION DES POSITIONS ========================
// Retcodes below are explicit server rejections: no execution should have occurred.
// Any unlisted result is treated conservatively as uncertain and must be reconciled.
bool PartialRetcodeDefinitiveReject(const uint rc) {
   return(rc == TRADE_RETCODE_REQUOTE ||
          rc == TRADE_RETCODE_REJECT ||
          rc == TRADE_RETCODE_CANCEL ||
          rc == TRADE_RETCODE_INVALID ||
          rc == TRADE_RETCODE_INVALID_VOLUME ||
          rc == TRADE_RETCODE_INVALID_PRICE ||
          rc == TRADE_RETCODE_INVALID_STOPS ||
          rc == TRADE_RETCODE_TRADE_DISABLED ||
          rc == TRADE_RETCODE_MARKET_CLOSED ||
          rc == TRADE_RETCODE_NO_MONEY ||
          rc == TRADE_RETCODE_PRICE_CHANGED ||
          rc == TRADE_RETCODE_PRICE_OFF ||
          rc == TRADE_RETCODE_INVALID_EXPIRATION);
}

// ATR simple (moyenne du vrai range) sur barres clôturées, sans handle d'indicateur :
// disponible immédiatement, y compris pour une position hors de l'univers courant.
double QuickATR(const string sym, const ENUM_TIMEFRAMES tf, const int period) {
   int n = MathMax(2, period);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(sym, tf, 1, n + 1, r) != n + 1) return(0.0);
   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += MathMax(r[i].high - r[i].low,
             MathMax(MathAbs(r[i].high - r[i + 1].close), MathAbs(r[i].low - r[i + 1].close)));
   return(sum / n);
}

void ManageOne(const ulong tk, SymState &s) {
   if(!PositionSelectByTicket(tk)) return;
   bool buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   ulong pid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   const bool isMR = (GVGet(KP("ST", pid), 0.0) > 1.5);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double vol = PositionGetDouble(POSITION_VOLUME);
   datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
   double bid = SymbolInfoDouble(s.name, SYMBOL_BID), ask = SymbolInfoDouble(s.name, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return;
   double px = buy ? bid : ask;

   if(InpNewsExitMin > 0 && NewsImminent(s, InpNewsExitMin)) { ClosePos(tk, "news imminente"); return; }

   double atr = 0;
   bool atrOK = (s.hAtr != INVALID_HANDLE) && Val(s.hAtr, 1, atr) && atr > 0;
   if(!atrOK) { atr = QuickATR(s.name, InpEntryTF, InpATRPeriod); atrOK = (atr > 0.0); }

   // A profit-side stop is valid after breakeven/profit-lock. Only a missing
   // stop is an emergency here; broker-side validity is checked against live Bid/Ask.
   if(sl <= 0.0) {
      if(atrOK) {
         double emergency = buy ? open - 1.5 * atr : open + 1.5 * atr;
         if(ModSL(tk, s.name, buy, emergency, tp)) { Log("SL d'urgence posé " + s.name); return; }
      }
      CloseRejected(tk, "position sans SL");
      return;
   }

   double r0 = GVGet(KP("R0", pid), 0.0);
   // Never infer the original R from the current SL: BE/trailing may already
   // have tightened it. If persisted R0 is missing, keep broker SL/TP protection
   // and the time-stop, but disable R-based partial/BE/trailing for this position.
   double prof = buy ? px - open : open - px;
   double R = (r0 > 0) ? prof / r0 : 0.0;

   if(InpUseTimeStop) {
      int openShift = iBarShift(s.name, InpEntryTF, ot, false);
      int held = (openShift >= 0) ? openShift : 0;
      if(isMR) {
         if(held >= InpMRMaxHoldBars) { ClosePos(tk, "MR time-stop R=" + DoubleToString(R, 2)); return; }
      } else if(held >= InpMaxHoldBars && R < InpTimeStopMinR) { ClosePos(tk, "time-stop R=" + DoubleToString(R, 2)); return; }
   }
   if(r0 <= 0) return;

   bool pdone = GlobalVariableCheck(KP("P1", pid));
   bool partialPending = GlobalVariableCheck(KP("PP", pid));
   datetime partialRetryAfter=(datetime)(long)GVGet(KP("PR",pid),0);

   // Reconcile a previously uncertain partial close before ever sending another one.
   if(partialPending) {
      double expectedRemain = GVGet(KP("PV",pid), vol) - GVGet(KP("PC",pid), 0.0);
      double stepNow = SymbolInfoDouble(s.name, SYMBOL_VOLUME_STEP);
      if(vol <= expectedRemain + MathMax(stepNow * 0.5, 1e-8)) {
         GlobalVariableSet(KP("P1", pid), 1.0);
         GlobalVariableDel(KP("PP", pid));
         GlobalVariableDel(KP("PV", pid));
         GlobalVariableDel(KP("PC", pid));
         GlobalVariableDel(KP("PT", pid));
         pdone = true;
         Log("Clôture partielle réconciliée depuis le volume réel " + s.name);
      } else {
         // Do not retry an uncertain request: this could close twice.
         // Keep managing the protected position (BE/trailing), but suppress new partial requests.
         pdone = true;
      }
   }

   if(InpUsePartial && !isMR && !pdone && R >= InpPartialR && TimeCurrent()>=partialRetryAfter) {
      double step = SymbolInfoDouble(s.name, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(s.name, SYMBOL_VOLUME_MIN);
      double cv = MathFloor(vol * InpPartialPct / 100.0 / step + 1e-9) * step;
      double rem = vol - cv;
      if(cv >= vmin - 1e-12 && rem >= vmin - 1e-12) {
         g_trade.SetDeviationInPoints(InpMaxDeviation);
         g_trade.SetTypeFillingBySymbol(s.name);
         double closeVol = NormalizeDouble(cv, VolDigits(step));
         bool partialSent = false;
         const double slBefore = sl, tpBefore = tp;
         // Persist intent BEFORE sending. A restart/timeout must not trigger a blind retry.
         GlobalVariableSet(KP("P1", pid), 1.0);
         GlobalVariableSet(KP("PP", pid), 1.0);
         GlobalVariableSet(KP("PV", pid), vol);
         GlobalVariableSet(KP("PC", pid), closeVol);
         GlobalVariableSet(KP("PT", pid), (double)TimeCurrent());
         if(IsHedgingAccount()) {
            partialSent = g_trade.PositionClosePartial(tk, closeVol);
         } else {
            if(buy) partialSent = g_trade.Sell(closeVol, s.name, 0.0, 0.0, 0.0, "BLACKHIPPO partial");
            else    partialSent = g_trade.Buy(closeVol, s.name, 0.0, 0.0, 0.0, "BLACKHIPPO partial");
         }
         uint rc = g_trade.ResultRetcode();
         GlobalVariableSet(KP("PR",pid),(double)(TimeCurrent()+30));
         if(partialSent && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL)) {
            bool volumeConfirmed = WaitVolumeAtMost(tk, vol - closeVol + step * 0.5);
            if(!volumeConfirmed) {
               Log("ATTENTION: exécution partielle annoncée mais volume non confirmé; verrou anti-doublon conservé " + s.name);
               return;
            }
            GlobalVariableDel(KP("PP", pid));
            GlobalVariableDel(KP("PV", pid));
            GlobalVariableDel(KP("PC", pid));
            GlobalVariableDel(KP("PT", pid));
            Log("Partiel confirmé " + s.name + " R=" + DoubleToString(R, 2));
            pdone = true;
            if(!IsHedgingAccount()) {
                  double tickSize = SymbolInfoDouble(s.name, SYMBOL_TRADE_TICK_SIZE);
                  double tol = (tickSize > 0 ? tickSize * 0.5 : s.point * 0.5);
                  bool protectedOK = false;
                  for(int retry = 0; retry < 3; retry++) {
                     if(!PositionSelectByTicket(tk)) break;
                     double slNow = PositionGetDouble(POSITION_SL);
                     double tpNow = PositionGetDouble(POSITION_TP);
                     if(MathAbs(slNow - slBefore) <= tol && MathAbs(tpNow - tpBefore) <= tol) {
                        protectedOK = true;
                        break;
                     }
                     bool modSent = g_trade.PositionModify(tk, slBefore, tpBefore);
                     uint modRC = g_trade.ResultRetcode();
                     Sleep(100);
                     if(!modSent || modRC != TRADE_RETCODE_DONE)
                        Log("Restauration NETTING tentative " + IntegerToString(retry + 1) +
                            " échouée " + s.name + " retcode=" + IntegerToString((int)modRC));
                  }
                  if(!protectedOK && PositionSelectByTicket(tk)) {
                     double slNow = PositionGetDouble(POSITION_SL);
                     double tpNow = PositionGetDouble(POSITION_TP);
                     protectedOK = (MathAbs(slNow - slBefore) <= tol && MathAbs(tpNow - tpBefore) <= tol);
                  }
                  if(!protectedOK) {
                     Log("CRITIQUE: protection NETTING non confirmée après partiel " + s.name +
                         "; fermeture de sécurité demandée.");
                     CloseRejected(tk, "SL/TP non restaurés après partiel NETTING");
                     return;
                  }
                  Log("Protection SL/TP confirmée après partiel NETTING " + s.name);
               }
         } else if(PartialRetcodeDefinitiveReject(rc)) {
            // Explicit server rejection: safe to release the intent and retry later.
            GlobalVariableDel(KP("P1", pid));
            GlobalVariableDel(KP("PP", pid));
            GlobalVariableDel(KP("PV", pid));
            GlobalVariableDel(KP("PC", pid));
            GlobalVariableDel(KP("PT", pid));
            Log("Clôture partielle rejetée sans exécution confirmée; nouvelle tentative différée " +
                s.name + " retcode=" + IntegerToString((int)rc));
         } else {
            // Timeout, connection loss, PLACED, generic error or unknown result:
            // keep persistent pending state and never issue a duplicate close blindly.
            Log("CRITIQUE: résultat de clôture partielle incertain; ordre verrouillé pour réconciliation " +
                s.name + " retcode=" + IntegerToString((int)rc) +
                " sent=" + (partialSent ? "true" : "false"));
            return;
         }
      } else {
         GlobalVariableSet(KP("P1", pid), 1.0);
         pdone = true;
      }
      if(!PositionSelectByTicket(tk)) return;
      sl = PositionGetDouble(POSITION_SL);
   }

   double beTrig = isMR ? InpMRBETriggerR : InpBETriggerR;
   if(InpUseBE && beTrig > 0.0 && R >= beTrig) {
      double off = (ask - bid) + InpBEOffsetPoints * s.point;
      double target = buy ? open + off : open - off;
      if((buy && sl < target) || (!buy && sl > target)) {
         if(ModSL(tk, s.name, buy, target, tp)) {
            if(!PositionSelectByTicket(tk)) return;
            sl = PositionGetDouble(POSITION_SL);
         }
      }
   }

   // Profit lock: after the trade has moved sufficiently in favor, move the SL
   // beyond breakeven by a configured fraction of initial R. It never widens risk.
   if(InpUseProfitLock && InpProfitLockTriggerR > 0.0 && InpProfitLockR > 0.0 &&
      R >= InpProfitLockTriggerR) {
      double costBuffer = (ask-bid) + InpBEOffsetPoints*s.point;
      double lockSL = buy ? open + InpProfitLockR*r0 + costBuffer
                          : open - InpProfitLockR*r0 - costBuffer;
      bool improves = buy ? (lockSL > sl) : (lockSL < sl);
      if(improves && ModSL(tk, s.name, buy, lockSL, tp)) {
         if(!PositionSelectByTicket(tk)) return;
         sl=PositionGetDouble(POSITION_SL);
      }
   }

   if(InpUseTrail && !isMR && atrOK && (pdone || R >= InpTrailStartR)) {
      double mult = InpTrailATR;
      if(GVGet(KP("AS", pid), 0.0) > 0.5) mult *= InpTrailStrongMult;
      double cand = buy ? px - mult * atr : px + mult * atr;
      bool better = buy ? (cand > sl + 0.1 * atr && cand > open) : (cand < sl - 0.1 * atr && cand < open);
      if(better) ModSL(tk, s.name, buy, cand, tp);
   }
}

void ManagePositions() {
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      int idx=SymIndex(sym);
      if(idx>=0) {
         ManageOne(tk,g_s[idx]);
         continue;
      }
      // Une position peut survivre à un changement de l'univers InpSymbols.
      // Créer un état temporaire minimal pour continuer SL d'urgence, time-stop,
      // BE/profit-lock/trailing et news-exit au lieu de l'abandonner.
      if(!SymbolSelect(sym,true)) {
         Print("CRITIQUE: symbole de position impossible à sélectionner: ",sym);
         continue;
      }
      SymState orphan;
      orphan.name=sym;
      orphan.hEmaF=INVALID_HANDLE; orphan.hEmaS=INVALID_HANDLE;
      orphan.hEmaT=INVALID_HANDLE; orphan.hRsi=INVALID_HANDLE;
      orphan.hAdx=INVALID_HANDLE; orphan.hAtr=INVALID_HANDLE;
      orphan.hAtrRef=INVALID_HANDLE; orphan.hH1=INVALID_HANDLE; orphan.hM15=INVALID_HANDLE;
      orphan.point=SymbolInfoDouble(sym,SYMBOL_POINT);
      orphan.digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      orphan.base=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      orphan.quote=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      orphan.lastExit=0; orphan.lastExitLoss=false;
      if(orphan.point>0.0) ManageOne(tk,orphan);
      else {
         // Dernier filet de sécurité : pas de position nue sans possibilité de gestion.
         if(PositionSelectByTicket(tk) && PositionGetDouble(POSITION_SL)<=0.0)
            CloseRejected(tk,"symbole hors univers, ATR indisponible et SL absent");
      }
   }
}

//======================== PROTECTIONS ========================
bool DailyGuard() {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_peak < eq) g_peak = eq;
   if(g_halted) {
      if(InpCloseOnHalt && (g_haltKind == HALT_LOSS || g_haltKind == HALT_WEEKLY)) CloseAll("halt retry");
      return(false);
   }
   if(EffectiveWeeklyLossPct() > 0 && g_weekEquity > 0) {
      double wl = (g_weekEquity - eq) / g_weekEquity * 100.0;
      if(wl >= EffectiveWeeklyLossPct()) {
         Halt(HALT_WEEKLY);
         Print("BLACKHIPPO: perte hebdomadaire atteinte (", DoubleToString(wl, 2), "%). Arrêt jusqu'à la semaine prochaine.");
         if(InpCloseOnHalt) CloseAll("weekly loss");
         return(false);
      }
   }
   if(g_dayEquity > 0) {
      double lossPct = (g_dayEquity - eq) / g_dayEquity * 100.0;
      if(EffectiveDailyLossPct() > 0 && lossPct >= EffectiveDailyLossPct()) {
         Halt(HALT_LOSS);
         Print("BLACKHIPPO: perte journalière atteinte (", DoubleToString(lossPct, 2), "%). Arrêt du jour.");
         if(InpCloseOnHalt) CloseAll("daily loss");
         return(false);
      }
      if(InpDailyProfitTargetPct > 0 && -lossPct >= InpDailyProfitTargetPct) {
         Halt(HALT_TARGET);
         Log("Objectif journalier atteint : entrées stoppées, positions conservées.");
         return(false);
      }
   }
   return(true);
}

void RegisterClosed(const ulong pid, const string sym, const double net) {
   PushRoll(net);
   double rm = GVGet(KP("RM", pid), 0.0);
   double rReal = (rm > 0) ? net / rm : 0.0;
   int st = (int)GVGet(KP("ST", pid), 0.0);
   string stTag = (st == 2) ? "MEAN_REVERSION" : ((st == 1) ? "BREAKOUT" : "PULLBACK");
   bool scratch = (rm > 0) ? (MathAbs(net) <= InpScratchFrac * rm) : (net == 0.0);
   bool loss = (net < 0 && !scratch);
   if(loss) g_consec++;
   else if(net > 0 && !scratch) g_consec = 0;
   if(InpMaxConsecLosses > 0 && g_consec >= InpMaxConsecLosses) {
      g_pauseUntil = TimeCurrent() + InpPauseMinutes * 60;
      g_consec = 0;
      Log("Pause " + IntegerToString(InpPauseMinutes) + " min après série de pertes");
   }
   int si = SymIndex(sym);
   if(si >= 0) { g_s[si].lastExit = TimeCurrent(); g_s[si].lastExitLoss = loss; }
   Csv("CLOSE", sym, 0, 0, 0, 0, net, rReal, "pid=" + IntegerToString((long)pid) + "|SETUP=" + stTag);
   GlobalVariableDel(KP("R0", pid)); GlobalVariableDel(KP("RM", pid));
   GlobalVariableDel(KP("P1", pid)); GlobalVariableDel(KP("PP", pid)); GlobalVariableDel(KP("PV", pid)); GlobalVariableDel(KP("PC", pid)); GlobalVariableDel(KP("PT", pid)); GlobalVariableDel(KP("AS", pid)); GlobalVariableDel(KP("PR", pid));
   GlobalVariableDel(KP("ST", pid));
   SaveState();
}

//======================== ENGINE ========================

//======================== EVENT DIAGNOSTICS ========================
// Journal passif : aucune action de trading ni modification du risque.
void WriteDiagnosticEvent(const string eventType,const string symbol,
                          const string details,const double value=0.0) {
   if(!InpEnableDiagnosticLog || MQLInfoInteger(MQL_TESTER)) return;
   int h=FileOpen(InpDiagnosticFile,
      FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON,';');
   if(h==INVALID_HANDLE) {
      Print("BLACKHIPPO: journal diagnostic indisponible, erreur=",GetLastError());
      return;
   }
   if(FileSize(h)==0)
      FileWrite(h,"local_time","server_time","event","symbol","magic","value","details");
   FileSeek(h,0,SEEK_END);
   datetime localNow=TimeLocal();
   datetime serverNow=TimeTradeServer();
   if(serverNow<=0) serverNow=TimeCurrent();
   FileWrite(h,TimeToString(localNow,TIME_DATE|TIME_SECONDS),
      TimeToString(serverNow,TIME_DATE|TIME_SECONDS),eventType,symbol,
      InpMagic,DoubleToString(value,2),details);
   FileClose(h);
}

//======================== HEALTH MONITOR ========================
// Diagnostic only: never sends orders, closes positions or changes risk.
void MonitorHealth() {
   if(!InpEnableHealthMonitor || MQLInfoInteger(MQL_TESTER)) return;
   datetime now = TimeCurrent();
   int interval = MathMax(10, InpHealthIntervalSec);
   if(g_lastHealthReport > 0 && (now - g_lastHealthReport) < interval) return;
   g_lastHealthReport = now;

   bool connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   bool algoAllowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
                      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginLevel = (margin > 0.0 ? AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) : 0.0);

   int ownPositions = 0;
   int missingSL = 0;
   int invalidSL = 0;
   double ownOpenRisk = 0.0;
   for(int p = PositionsTotal() - 1; p >= 0; p--) {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ownPositions++;
      string psym = PositionGetString(POSITION_SYMBOL);
      bool pbuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double popen = PositionGetDouble(POSITION_PRICE_OPEN);
      double psl = PositionGetDouble(POSITION_SL);
      double pvol = PositionGetDouble(POSITION_VOLUME);
      if(psl <= 0.0) missingSL++;
      else {
         double pBid=SymbolInfoDouble(psym,SYMBOL_BID);
         double pAsk=SymbolInfoDouble(psym,SYMBOL_ASK);
         if(pBid<=0.0 || pAsk<=0.0 || (pbuy && psl>=pBid) || (!pbuy && psl<=pAsk)) invalidSL++;
      }
      ownOpenRisk += PosRiskMoney(psym, pbuy, popen, psl, pvol);
   }

   int staleQuotes = 0;
   int worstQuoteAge = 0;
   string staleList = "";
   int maxAge = MathMax(10, InpHealthMaxQuoteAgeSec);
   for(int i = 0; i < g_n; i++) {
      MqlTick tick;
      if(!SymbolInfoTick(g_s[i].name, tick) || tick.time <= 0) {
         staleQuotes++;
         if(staleList != "") staleList += ",";
         staleList += g_s[i].name + ":NO_TICK";
         continue;
      }
      int age = (int)MathMax(0, now - tick.time);
      if(age > worstQuoteAge) worstQuoteAge = age;
      if(age > maxAge) {
         staleQuotes++;
         if(staleList != "") staleList += ",";
         staleList += g_s[i].name + ":" + IntegerToString(age) + "s";
      }
   }

   // Bit flags: 1=disconnected, 2=algo disabled, 4=own position without SL,
   // 8=stale quotes, 16=low margin level, 32=open risk above SAFE ceiling,
   // 64=own position with SL crossed/invalid relative to current Bid/Ask.
   // Diagnostic only: no automatic liquidation is initiated by the monitor.
   double riskLimitMoney = equity * EffectiveTotalRiskPct() / 100.0;
   bool lowMargin = (margin > 0.0 && marginLevel > 0.0 && marginLevel < 200.0);
   bool riskOver = (ownOpenRisk > riskLimitMoney + 0.01);
   int flags = 0;
   if(!connected) flags |= 1;
   if(!algoAllowed) flags |= 2;
   if(missingSL > 0) flags |= 4;
   if(staleQuotes > 0) flags |= 8;
   if(lowMargin) flags |= 16;
   if(riskOver) flags |= 32;
   if(invalidSL > 0) flags |= 64;

   string state = (flags == 0 ? "OK" : "ALERTE");
   string line = "HEALTH " + state +
      " | equity=" + DoubleToString(equity,2) +
      " | balance=" + DoubleToString(balance,2) +
      " | free_margin=" + DoubleToString(freeMargin,2) +
      " | margin_level=" + DoubleToString(marginLevel,1) +
      " | positions_magic=" + IntegerToString(ownPositions) +
      " | open_risk_magic=" + DoubleToString(ownOpenRisk,2) +
      " | risk_limit=" + DoubleToString(riskLimitMoney,2) +
      " | missing_SL=" + IntegerToString(missingSL) +
      " | invalid_side_SL=" + IntegerToString(invalidSL) +
      " | stale_quotes=" + IntegerToString(staleQuotes) +
      " | worst_quote_age_sec=" + IntegerToString(worstQuoteAge) +
      " | connected=" + (connected ? "1" : "0") +
      " | algo_allowed=" + (algoAllowed ? "1" : "0");
   if(staleList != "") line += " | stale_symbols=" + staleList;

   if(flags != g_lastHealthFlags) {
      WriteDiagnosticEvent("HEALTH_"+state,"",line,(double)flags);
      Print("CLY.MO ", line);
      if(missingSL > 0)
         Print("CLY.MO CRITIQUE: ", missingSL,
               " position(s) du Magic ", InpMagic,
               " sans Stop Loss. Vérification immédiate requise.");
      if(invalidSL > 0)
         Print("CLY.MO CRITIQUE: ", invalidSL,
               " position(s) du Magic ", InpMagic,
               " avec Stop Loss du mauvais côté du prix d'ouverture.");
      if(lowMargin) Print("CLY.MO WARNING: niveau de marge faible: ",DoubleToString(marginLevel,1),"%");
      if(riskOver) Print("CLY.MO WARNING: risque ouvert Magic supérieur au plafond SAFE: ",
                         DoubleToString(ownOpenRisk,2)," > ",DoubleToString(riskLimitMoney,2));
      g_lastHealthFlags = flags;
   }

   int fh = FileOpen("CLY_MO_Health.csv",
      FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON, ';');
   if(fh != INVALID_HANDLE) {
      if(FileSize(fh) == 0)
         FileWrite(fh,"time","status","flags","equity","balance","free_margin",
                      "margin_level","own_positions","open_risk_magic","risk_limit",
                      "missing_sl","invalid_side_sl","stale_quotes","worst_quote_age_sec","connected",
                      "algo_allowed","stale_symbols");
      FileSeek(fh,0,SEEK_END);
      FileWrite(fh,TimeToString(now,TIME_DATE|TIME_SECONDS),state,flags,
         DoubleToString(equity,2),DoubleToString(balance,2),
         DoubleToString(freeMargin,2),DoubleToString(marginLevel,1),
         ownPositions,DoubleToString(ownOpenRisk,2),DoubleToString(riskLimitMoney,2),
         missingSL,invalidSL,staleQuotes,worstQuoteAge,
         (connected ? 1 : 0),(algoAllowed ? 1 : 0),staleList);
      FileClose(fh);
   } else {
      Print("CLY.MO: impossible d'écrire le journal de santé, erreur=",GetLastError());
   }
}

// Forward declarations used by dashboard event handlers.
bool QuickConfigCanArm(string &reason);
void QuickConfigPreflight();
void WriteConfigSnapshot();

//======================== CHART DASHBOARD (MULTI-PAGE) ========================
// Dashboard multi-pages avec page Risque éditable.
// Les boutons ne passent jamais d'ordres.

string DashObj(const string suffix) {
   return "CLYMO_DASH_" + IntegerToString((long)ChartID()) + "_" + IntegerToString((long)InpMagic) + "_" + suffix;
}

void DashDeleteAll() {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--) {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, "CLYMO_DASH_" + IntegerToString((long)ChartID())) == 0)
         ObjectDelete(0, name);
   }
}

void DashCreateRect(const string suffix, int x, int y, int w, int h, color bg, color border) {
   string name = DashObj(suffix);
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpDashboardX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpDashboardY + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DashCreateLabel(const string suffix, int x, int y, int fontSize, color clr, const string text="") {
   string name = DashObj(suffix);
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpDashboardX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpDashboardY + y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DashCreateButton(const string suffix, int x, int y, int w, int h, const string caption, color bg, color border=C'90,100,115') {
   string name = DashObj(suffix);
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpDashboardX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpDashboardY + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TEXT, caption);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
}

void DashDraftLoadFromEffective() {
   g_draft.riskPercent        = g_effRiskPercent;
   g_draft.maxRiskPerTrade    = g_effMaxRiskPerTrade;
   g_draft.maxTotalRiskPct    = g_effMaxTotalRiskPct;
   g_draft.maxCurrencyRiskPct = g_effMaxCurrencyRiskPct;
   g_draft.maxOpenTrades      = g_effMaxOpenTrades;
   g_draft.maxSameDirection   = g_effMaxSameDirection;
   g_draft.maxTradesPerDay    = g_effMaxTradesPerDay;
   g_draft.maxDailyLossPct    = g_effMaxDailyLossPct;
   g_draft.maxWeeklyLossPct   = g_effMaxWeeklyLossPct;
   g_dashDirty = false;
}

void InitEffectiveRiskParams() {
   g_effRiskPercent        = InpRiskPercent;
   g_effMaxRiskPerTrade    = InpMaxRiskPerTrade;
   g_effMaxTotalRiskPct    = InpMaxTotalRiskPct;
   g_effMaxCurrencyRiskPct = InpMaxCurrencyRiskPct;
   g_effMaxOpenTrades      = InpMaxOpenTrades;
   g_effMaxSameDirection   = InpMaxSameDirection;
   g_effMaxTradesPerDay    = InpMaxTradesPerDay;
   g_effMaxDailyLossPct    = InpMaxDailyLossPct;
   g_effMaxWeeklyLossPct   = InpMaxWeeklyLossPct;
   DashDraftLoadFromEffective();
}

void DashBuildTabs() {
   string tabs[7] = {"Accueil","Risque","Signal","MeanRev","Sorties","Filtres","Avancé"};
   int tabW = 68;
   for(int i=0; i<7; i++) {
      color bg = (g_dashPage == (DASH_PAGE)i) ? C'35,105,160' : C'48,56,68';
      color br = (g_dashPage == (DASH_PAGE)i) ? clrDeepSkyBlue : C'90,100,115';
      DashCreateButton("TAB_"+IntegerToString(i), 8+i*(tabW+3), 8, tabW, 24, tabs[i], bg, br);
   }
}

void DashBuildFooter() {
   color applyBg = g_dashDirty ? C'35,130,70' : C'60,70,80';
   DashCreateButton("BTN_APPLY",  12, 430, 120, 26, "Appliquer", applyBg);
   DashCreateButton("BTN_CANCEL", 140, 430, 120, 26, "Annuler", C'100,60,50');
   DashCreateButton("BTN_ARM",    280, 430, 140, 26,
                    g_entriesArmed ? "PAUSE ENTREES" : "ARMER ENTREES",
                    g_entriesArmed ? C'145,65,45' : C'35,115,75');
   if(g_dashDirty)
      DashCreateLabel("LBL_DIRTY", 12, 405, 9, clrOrange, "Modifications non appliquées");
   else
      DashCreateLabel("LBL_DIRTY", 12, 405, 9, clrSilver, "Aucune modification en attente");
}

void DashBuildHome() {
   DashCreateLabel("TITLE", 12, 42, 11, clrWhite, "BLACKHIPPO BUFFALO-PELERIN  |  QUICK CONFIG");

   string state = "MODE SURVEILLANCE";
   color  stateClr = clrOrange;
   if(g_halted)             { state = "HALTE DE SECURITE ACTIVE"; stateClr = clrTomato; }
   else if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { state = "DECONNECTE DU COURTIER"; stateClr = clrTomato; }
   else if(!TradingAllowed()){ state = "TRADING NON AUTORISE"; stateClr = clrTomato; }
   else if((InpUseCalendarFile || InpUseNativeCalendar || InpUseCalendarWebRequest) && !g_newsOK && InpFailClosedCalendar)
                            { state = "ATTENTE — CALENDRIER INDISPONIBLE"; stateClr = clrOrange; }
   else if(!g_entriesArmed) { state = "ENTREES DESARMEES"; stateClr = clrOrange; }
   else                     { state = "ENTREES ARMEES — SURVEILLANCE ACTIVE"; stateClr = clrLimeGreen; }

   DashCreateLabel("STATE", 12, 68, 10, stateClr, state);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   DashCreateLabel("LINE_1", 12, 95, 9, clrGainsboro,
      "Compte: " + (IsHedgingAccount() ? "HEDGING" : "NETTING") +
      "  |  Equity: " + DoubleToString(equity, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));

   DashCreateLabel("LINE_2", 12, 115, 9, clrGainsboro,
      "Profil: " + RiskProfileName() + "  |  Risque cible max: " +
      DoubleToString(EffectiveRiskPerTradePct(), 2) + "%");

   double openRisk = OpenRiskTotal();
   double riskCap  = equity * EffectiveTotalRiskPct() / 100.0;
   color riskClr = (openRisk > riskCap + 0.01) ? clrTomato : clrGainsboro;
   DashCreateLabel("LINE_3", 12, 135, 9, riskClr,
      "Risque portefeuille: " + DoubleToString(openRisk, 2) + " / " + DoubleToString(riskCap, 2));

   DashCreateLabel("LINE_4", 12, 155, 9, clrGainsboro,
      "Positions EA: " + IntegerToString(CountOpen()) + " / " + IntegerToString(EffectiveMaxOpenTrades()) +
      "   |   Univers: " + IntegerToString(g_n) + (InpTradeOnlyCurrent ? " (graphique)" : " (multi)"));

   DashCreateButton("BTN_SAFE",     12, 190, 90, 26, "SAFE",
      g_activeRiskProfile==CLY_RISK_SAFE ? C'35,105,160' : C'48,56,68');
   DashCreateButton("BTN_BALANCED", 110,190, 90, 26, "BALANCED",
      g_activeRiskProfile==CLY_RISK_BALANCED ? C'35,105,160' : C'48,56,68');
   DashCreateButton("BTN_DYNAMIC",  208,190, 90, 26, "DYNAMIC",
      g_activeRiskProfile==CLY_RISK_DYNAMIC ? C'35,105,160' : C'48,56,68');
   DashCreateButton("BTN_CUSTOM",   306,190, 90, 26, "CUSTOM",
      g_activeRiskProfile==CLY_RISK_CUSTOM ? C'35,105,160' : C'48,56,68');

   DashCreateButton("BTN_DIAG", 12, 230, 160, 26, "DIAGNOSTIC", C'48,70,100');
}

void DashBuildRisk() {
   DashCreateLabel("TITLE", 12, 42, 11, clrWhite, "CONFIGURATION — RISQUE");
   int y = 78;
   int lineH = 32;

   DashCreateLabel("LBL_R1", 12, y, 9, clrSilver, "Risque % par trade");
   DashCreateLabel("LBL_R1V", 175, y, 9, clrWhite, DoubleToString(g_draft.riskPercent, 2) + " %");
   DashCreateButton("BTN_R1_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R1_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');
   y += lineH;

   DashCreateLabel("LBL_R2", 12, y, 9, clrSilver, "Plafond dur / trade");
   DashCreateLabel("LBL_R2V", 175, y, 9, clrWhite, DoubleToString(g_draft.maxRiskPerTrade, 2) + " %");
   DashCreateButton("BTN_R2_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R2_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');
   y += lineH;

   DashCreateLabel("LBL_R3", 12, y, 9, clrSilver, "Risque total portefeuille");
   DashCreateLabel("LBL_R3V", 175, y, 9, clrWhite, DoubleToString(g_draft.maxTotalRiskPct, 2) + " %");
   DashCreateButton("BTN_R3_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R3_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');
   y += lineH;

   DashCreateLabel("LBL_R4", 12, y, 9, clrSilver, "Risque max par devise");
   DashCreateLabel("LBL_R4V", 175, y, 9, clrWhite, DoubleToString(g_draft.maxCurrencyRiskPct, 2) + " %");
   DashCreateButton("BTN_R4_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R4_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');
   y += lineH;

   DashCreateLabel("LBL_R5", 12, y, 9, clrSilver, "Max trades ouverts");
   DashCreateLabel("LBL_R5V", 175, y, 9, clrWhite, IntegerToString(g_draft.maxOpenTrades));
   DashCreateButton("BTN_R5_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R5_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');
   y += lineH;

   DashCreateLabel("LBL_R6", 12, y, 9, clrSilver, "Max même direction");
   DashCreateLabel("LBL_R6V", 175, y, 9, clrWhite, IntegerToString(g_draft.maxSameDirection));
   DashCreateButton("BTN_R6_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R6_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');
   y += lineH;

   DashCreateLabel("LBL_R7", 12, y, 9, clrSilver, "Perte journalière max");
   DashCreateLabel("LBL_R7V", 175, y, 9, clrWhite, DoubleToString(g_draft.maxDailyLossPct, 2) + " %");
   DashCreateButton("BTN_R7_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R7_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');
   y += lineH;

   DashCreateLabel("LBL_R8", 12, y, 9, clrSilver, "Perte hebdomadaire max");
   DashCreateLabel("LBL_R8V", 175, y, 9, clrWhite, DoubleToString(g_draft.maxWeeklyLossPct, 2) + " %");
   DashCreateButton("BTN_R8_MINUS", 270, y-2, 34, 22, "-", C'70,50,50');
   DashCreateButton("BTN_R8_PLUS",  310, y-2, 34, 22, "+", C'40,80,50');

   DashCreateLabel("LBL_INFO", 12, 370, 8, clrSilver, "Les profils SAFE/BALANCED/DYNAMIC plafonnent automatiquement ces valeurs.");
}

string OnOff(const bool b) { return(b ? "ON" : "OFF"); }
string D2(const double v, const int d = 2) { return(DoubleToString(v, d)); }
string TFName(const ENUM_TIMEFRAMES tf) { return(StringSubstr(EnumToString(tf), 7)); }

void DashLine(const int idx, const string text, const color clr = clrGainsboro) {
   DashCreateLabel("LN_" + IntegerToString(idx), 12, 70 + idx * 20, 9, clr, text);
}

void DashReadOnlyNote() {
   DashCreateLabel("LBL_RO", 12, 382, 8, clrSilver, "Lecture seule : modifier ces réglages via les inputs de l'EA.");
}

void DashBuildSignal() {
   DashCreateLabel("TITLE", 12, 42, 11, clrWhite, "CONFIGURATION — SIGNAL (lecture seule)");
   DashLine(0, "Score : seuil " + D2(InpScoreBaseThreshold, 0) + " | marge min " + D2(InpMinScoreMargin, 1) +
               " | adaptatif " + OnOff(InpUseAdaptiveScoring));
   DashLine(1, "Setups : Pullback " + OnOff(InpUsePullbackSetup) + " | Breakout " + OnOff(InpUseBreakoutSetup) +
               " | points min " + D2(InpMinSetupPoints, 0));
   DashLine(2, "EMA " + IntegerToString(InpEMAFast) + "/" + IntegerToString(InpEMASlow) + "/" + IntegerToString(InpEMATrend) +
               " | TF " + TFName(InpEntryTF) + "/" + TFName(InpConfirmTF) + "/" + TFName(InpHigherTF));
   DashLine(3, "ADX min " + D2(InpADXMin, 0) + " fort " + D2(InpADXStrong, 0) + " | ER min " + D2(InpMinER) + " fort " + D2(InpStrongER));
   DashLine(4, "Garde-fous durs " + OnOff(InpHardRegimeGate) + " | ATR x" + D2(InpHardATRRatioMult) +
               " bougie x" + D2(InpHardCandleMult) + " ext. x" + D2(InpHardExtensionMult));
   DashLine(5, "Anti-poursuite : base " + D2(InpMaxEntryDistanceATR) + " ATR | max adaptatif " + D2(InpAdaptiveMaxDistanceATR) + " ATR");
   DashLine(6, "RR base " + D2(InpRRBase) + " | fort " + D2(InpRRStrong) + " | coût max/TP " + D2(InpMaxCostToTP * 100.0, 0) + "%");
   DashLine(7, "SL structurel : " + IntegerToString(InpStructBars) + " barres | " + D2(InpMinStructATR) + " à " + D2(InpMaxStructATR) + " ATR");
   DashLine(8, "Régimes " + OnOff(InpUseRegimeEngine) + " | vol-targeting " + OnOff(InpUseVolTargeting) +
               " | budget jour " + D2(InpDailyRiskBudgetPct) + "%");
   DashReadOnlyNote();
}

void DashBuildMR() {
   DashCreateLabel("TITLE", 12, 42, 11, clrWhite, "CONFIGURATION — MEAN REVERSION (lecture seule)");
   DashLine(0, "Moteur mean reversion : " + OnOff(InpUseMeanReversion));
   DashLine(1, "Bandes " + IntegerToString(InpMRBandsPeriod) + " / " + D2(InpMRBandsDeviation, 1) +
               " | RSI achat <= " + D2(InpMRRSIBuy, 0) + " vente >= " + D2(InpMRRSISell, 0));
   DashLine(2, "Régime range : ADX <= " + D2(InpMRADXMax, 0) + " | ER <= " + D2(InpMRERMax));
   DashLine(3, "Score min " + D2(InpMRScoreThreshold, 0) + " | RR min " + D2(InpMRMinRR));
   DashLine(4, "Cible : " + (InpMRUseOppositeBand ? "bande opposée" : "médiane"));
   DashLine(5, "Time-stop " + IntegerToString(InpMRMaxHoldBars) + " barres | BE à " + D2(InpMRBETriggerR) + "R");
   DashLine(6, "Volume >= " + D2(InpMRVolSpikeMult) + " x moyenne | risque x" + D2(InpMRRiskMult));
   DashLine(7, "Coût max/TP " + D2(InpMRMaxCostToTP * 100.0, 0) + "% | pente H1 max " + D2(InpMRH1FlatATR) + " ATR");
   DashReadOnlyNote();
}

void DashBuildExits() {
   DashCreateLabel("TITLE", 12, 42, 11, clrWhite, "CONFIGURATION — SORTIES (lecture seule)");
   DashLine(0, "Partiel " + OnOff(InpUsePartial) + " | " + D2(InpPartialPct, 0) + "% à " + D2(InpPartialR) + "R");
   DashLine(1, "Break-even " + OnOff(InpUseBE) + " | à " + D2(InpBETriggerR) + "R | offset " + D2(InpBEOffsetPoints, 0) + " pts + spread");
   DashLine(2, "Trailing " + OnOff(InpUseTrail) + " | dès " + D2(InpTrailStartR) + "R | " + D2(InpTrailATR) +
               " ATR (x" + D2(InpTrailStrongMult) + " si ADX fort)");
   DashLine(3, "Verrou de gain " + OnOff(InpUseProfitLock) + " | à " + D2(InpProfitLockTriggerR) + "R, SL à +" + D2(InpProfitLockR) + "R");
   DashLine(4, "Time-stop " + OnOff(InpUseTimeStop) + " | " + IntegerToString(InpMaxHoldBars) + " barres si R < " + D2(InpTimeStopMinR));
   DashLine(5, "Sortie avant news : " + IntegerToString(InpNewsExitMin) + " min");
   DashLine(6, "Clôture session " + StringFormat("%02d:%02d", InpCloseHour, InpCloseMinute) +
               " (vendredi " + StringFormat("%02d:%02d", InpFridayCloseHour, InpFridayCloseMinute) + ")");
   DashReadOnlyNote();
}

void DashBuildFilters() {
   DashCreateLabel("TITLE", 12, 42, 11, clrWhite, "CONFIGURATION — FILTRES (lecture seule)");
   DashLine(0, "Entrées (heure serveur) " + StringFormat("%02d:00-%02d:00", InpStartHour, InpEndHour) +
               " | vendredi jusqu'à " + IntegerToString(InpFridayEndHour) + "h");
   DashLine(1, "Ignorer " + IntegerToString(InpSkipOpenMin) + " min après l'ouverture");
   DashLine(2, "Calendrier " + (g_newsOK ? "VALIDE" : "NON VALIDE") + " | événements " + IntegerToString(ArraySize(g_news)) +
               " | fail-closed " + OnOff(InpFailClosedCalendar),
            (g_newsOK ? clrGainsboro : clrOrange));
   DashLine(3, "Impact min " + IntegerToString(InpCalMinImpact) + " | blocage -" + IntegerToString(InpCalMinBefore) +
               " / +" + IntegerToString(InpCalMinAfter) + " min");
   DashLine(4, "Spread max " + D2(InpMaxSpreadPoints, 0) + " pts | " + D2(InpMaxSpreadATRFrac * 100.0, 0) +
               "% ATR | percentile " + D2(InpSpreadPctileMax * 100.0, 0) + "%");
   DashLine(5, "Corrélation max |r| " + D2(InpMaxCorrelation));
   DashLine(6, "Cooldown sortie " + IntegerToString(InpCooldownExitBars) + " | perte " + IntegerToString(InpCooldownLossBars) +
               " | entrée " + IntegerToString(InpCooldownBars) + " barres");
   DashLine(7, "Pause " + IntegerToString(InpPauseMinutes) + " min après " + IntegerToString(InpMaxConsecLosses) + " pertes");
   DashLine(8, "Marge max " + D2(EffectiveMarginUsePct(), 0) + "%");
   DashReadOnlyNote();
}

void DashBuildAdvanced() {
   DashCreateLabel("TITLE", 12, 42, 11, clrWhite, "CONFIGURATION — AVANCÉ (lecture seule)");
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_peak > 0.0) ? (g_peak - eq) / g_peak * 100.0 : 0.0;
   DashLine(0, "Magic " + IntegerToString((long)InpMagic) + " | " + (InpTradeOnlyCurrent ? "graphique seul" : "multi-symboles") +
               " | univers " + IntegerToString(g_n));
   DashLine(1, "Profil " + RiskProfileName() + " | mémorisé " + OnOff(InpRememberRiskProfile) + " | forcer input " + OnOff(InpForceInputProfile));
   DashLine(2, "Armement manuel " + OnOff(InpRequireManualArm) + " | réarmement manuel après halte " + OnOff(InpHaltRequiresManualRearm));
   DashLine(3, "Halte : " + (g_halted ? ("ACTIVE (type " + IntegerToString(g_haltKind) + ")") : "non"), (g_halted ? clrTomato : clrGainsboro));
   DashLine(4, "Pic equity " + D2(g_peak) + " | drawdown " + D2(dd) + "%");
   DashLine(5, "Pertes consécutives " + IntegerToString(g_consec) + " | fills rejetés " + IntegerToString(g_badFills));
   DashLine(6, "Santé " + OnOff(InpEnableHealthMonitor) + " | diagnostic " + OnOff(InpEnableDiagnosticLog) +
               " | export config " + OnOff(InpEnableConfigBridge));
   DashReadOnlyNote();
}

void DashboardRefresh() {
   if(!InpShowDashboard || MQLInfoInteger(MQL_TESTER)) return;
   // Les objets sont mis à jour sur place ; on ne supprime tout que lors d'un changement de page
   // (plus de clignotement ni de clics perdus pendant la recréation).
   if(g_dashBuiltPage != (int)g_dashPage) { DashDeleteAll(); g_dashBuiltPage = (int)g_dashPage; }
   DashCreateRect("BG", 0, 0, 460, 470, C'20,25,34', C'75,85,100');
   DashBuildTabs();
   switch(g_dashPage) {
      case PAGE_HOME:     DashBuildHome();     break;
      case PAGE_RISK:     DashBuildRisk();     break;
      case PAGE_SIGNAL:   DashBuildSignal();   break;
      case PAGE_MR:       DashBuildMR();       break;
      case PAGE_EXITS:    DashBuildExits();    break;
      case PAGE_FILTERS:  DashBuildFilters();  break;
      case PAGE_ADVANCED: DashBuildAdvanced(); break;
   }
   DashBuildFooter();
   ChartRedraw(0);
}

void DashboardRemove() {
   DashDeleteAll();
   g_dashBuiltPage = -1;
}

void DashboardRefreshThrottled() {
   static uint lastDash = 0;
   uint nowMs = GetTickCount();
   if(nowMs - lastDash < 1000) return;
   lastDash = nowMs;
   DashboardRefresh();
}

bool DashHandleRiskButtons(const string sparam) {
   bool changed = false;
   double stepSmall = 0.05, stepMed = 0.25;
   int stepInt = 1;

   if(sparam == DashObj("BTN_R1_MINUS")) { g_draft.riskPercent = MathMax(0.05, g_draft.riskPercent - stepSmall); changed = true; }
   if(sparam == DashObj("BTN_R1_PLUS"))  { g_draft.riskPercent = MathMin(3.00, g_draft.riskPercent + stepSmall); changed = true; }
   if(sparam == DashObj("BTN_R2_MINUS")) { g_draft.maxRiskPerTrade = MathMax(0.10, g_draft.maxRiskPerTrade - stepSmall); changed = true; }
   if(sparam == DashObj("BTN_R2_PLUS"))  { g_draft.maxRiskPerTrade = MathMin(5.00, g_draft.maxRiskPerTrade + stepSmall); changed = true; }
   if(sparam == DashObj("BTN_R3_MINUS")) { g_draft.maxTotalRiskPct = MathMax(0.30, g_draft.maxTotalRiskPct - stepMed); changed = true; }
   if(sparam == DashObj("BTN_R3_PLUS"))  { g_draft.maxTotalRiskPct = MathMin(10.0, g_draft.maxTotalRiskPct + stepMed); changed = true; }
   if(sparam == DashObj("BTN_R4_MINUS")) { g_draft.maxCurrencyRiskPct = MathMax(0.20, g_draft.maxCurrencyRiskPct - stepMed); changed = true; }
   if(sparam == DashObj("BTN_R4_PLUS"))  { g_draft.maxCurrencyRiskPct = MathMin(5.00, g_draft.maxCurrencyRiskPct + stepMed); changed = true; }
   if(sparam == DashObj("BTN_R5_MINUS")) { g_draft.maxOpenTrades = MathMax(1, g_draft.maxOpenTrades - stepInt); changed = true; }
   if(sparam == DashObj("BTN_R5_PLUS"))  { g_draft.maxOpenTrades = MathMin(15, g_draft.maxOpenTrades + stepInt); changed = true; }
   if(sparam == DashObj("BTN_R6_MINUS")) { g_draft.maxSameDirection = MathMax(1, g_draft.maxSameDirection - stepInt); changed = true; }
   if(sparam == DashObj("BTN_R6_PLUS"))  { g_draft.maxSameDirection = MathMin(10, g_draft.maxSameDirection + stepInt); changed = true; }
   if(sparam == DashObj("BTN_R7_MINUS")) { g_draft.maxDailyLossPct = MathMax(0.50, g_draft.maxDailyLossPct - stepMed); changed = true; }
   if(sparam == DashObj("BTN_R7_PLUS"))  { g_draft.maxDailyLossPct = MathMin(15.0, g_draft.maxDailyLossPct + stepMed); changed = true; }
   if(sparam == DashObj("BTN_R8_MINUS")) { g_draft.maxWeeklyLossPct = MathMax(1.00, g_draft.maxWeeklyLossPct - stepMed); changed = true; }
   if(sparam == DashObj("BTN_R8_PLUS"))  { g_draft.maxWeeklyLossPct = MathMin(25.0, g_draft.maxWeeklyLossPct + stepMed); changed = true; }

   if(changed) {
      g_dashDirty = true;
      DashboardRefresh();
   }
   return changed;
}

bool DashDraftValidate(string &why) {
   why = "";
   if(g_draft.riskPercent > g_draft.maxRiskPerTrade) { why = "le risque par trade dépasse le plafond dur par trade"; return(false); }
   if(g_draft.maxTotalRiskPct < g_draft.maxRiskPerTrade) { why = "le risque total est inférieur au plafond par trade"; return(false); }
   if(g_draft.maxCurrencyRiskPct < g_draft.maxRiskPerTrade) { why = "le plafond par devise est inférieur au plafond par trade (aucune entrée possible)"; return(false); }
   if(g_draft.maxDailyLossPct > 0.0 && g_draft.maxWeeklyLossPct > 0.0 && g_draft.maxWeeklyLossPct < g_draft.maxDailyLossPct) {
      why = "la perte hebdomadaire doit être supérieure ou égale à la perte journalière"; return(false);
   }
   return(true);
}

// true si le brouillon assouplit au moins une limite par rapport aux valeurs actives
bool DashDraftLoosens() {
   return(g_draft.riskPercent        > g_effRiskPercent        + 1e-9 ||
          g_draft.maxRiskPerTrade    > g_effMaxRiskPerTrade    + 1e-9 ||
          g_draft.maxTotalRiskPct    > g_effMaxTotalRiskPct    + 1e-9 ||
          g_draft.maxCurrencyRiskPct > g_effMaxCurrencyRiskPct + 1e-9 ||
          g_draft.maxOpenTrades      > g_effMaxOpenTrades      ||
          g_draft.maxSameDirection   > g_effMaxSameDirection   ||
          g_draft.maxTradesPerDay    > g_effMaxTradesPerDay    ||
          g_draft.maxDailyLossPct    > g_effMaxDailyLossPct    + 1e-9 ||
          g_draft.maxWeeklyLossPct   > g_effMaxWeeklyLossPct   + 1e-9);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id != CHARTEVENT_OBJECT_CLICK || !InpShowDashboard || MQLInfoInteger(MQL_TESTER)) return;

   // Navigation onglets
   for(int i=0; i<7; i++) {
      if(sparam == DashObj("TAB_"+IntegerToString(i))) {
         g_dashPage = (DASH_PAGE)i;
         DashboardRefresh();
         return;
      }
   }

   // Boutons +/- page Risque
   if(DashHandleRiskButtons(sparam)) return;

   // Profils
   if(sparam == DashObj("BTN_SAFE") || sparam == DashObj("BTN_BALANCED") ||
      sparam == DashObj("BTN_DYNAMIC") || sparam == DashObj("BTN_CUSTOM")) {
      if(g_entriesArmed) {
         g_entriesArmed = false;
         Log("Changement de profil → entrées automatiquement désarmées");
      }
      if(sparam == DashObj("BTN_SAFE"))     g_activeRiskProfile = CLY_RISK_SAFE;
      if(sparam == DashObj("BTN_BALANCED")) g_activeRiskProfile = CLY_RISK_BALANCED;
      if(sparam == DashObj("BTN_DYNAMIC"))  g_activeRiskProfile = CLY_RISK_DYNAMIC;
      if(sparam == DashObj("BTN_CUSTOM"))   g_activeRiskProfile = CLY_RISK_CUSTOM;
      if(InpRememberRiskProfile) GlobalVariableSet(K("risk_profile"), (double)g_activeRiskProfile);
      Log("Profil sélectionné: " + RiskProfileName());
      WriteConfigSnapshot();
      DashboardRefresh();
      return;
   }

   // Armement
   if(sparam == DashObj("BTN_ARM")) {
      if(g_entriesArmed) {
         g_entriesArmed = false;
         Log("Nouvelles entrées désarmées depuis le tableau de bord.");
      } else {
         string reason = "";
         if(QuickConfigCanArm(reason)) {
            g_entriesArmed = true;
            Log("Nouvelles entrées armées après validation QUICK CONFIG.");
         } else {
            g_entriesArmed = false;
            Print("BLACKHIPPO — ARMEMENT REFUSÉ : ", reason);
            Alert("CLY.MO PRO : armement refusé. ", reason);
         }
      }
      WriteConfigSnapshot();
      DashboardRefresh();
      return;
   }

   // Diagnostic
   if(sparam == DashObj("BTN_DIAG")) {
      QuickConfigPreflight();
      return;
   }

   // Appliquer
   if(sparam == DashObj("BTN_APPLY")) {
      string whyBad = "";
      if(!DashDraftValidate(whyBad)) {
         Print("BLACKHIPPO — MODIFICATIONS REFUSÉES : ", whyBad);
         Alert("BLACKHIPPO : modifications refusées. ", whyBad);
         return;
      }
      bool loosened = DashDraftLoosens();
      g_effRiskPercent        = g_draft.riskPercent;
      g_effMaxRiskPerTrade    = g_draft.maxRiskPerTrade;
      g_effMaxTotalRiskPct    = g_draft.maxTotalRiskPct;
      g_effMaxCurrencyRiskPct = g_draft.maxCurrencyRiskPct;
      g_effMaxOpenTrades      = g_draft.maxOpenTrades;
      g_effMaxSameDirection   = g_draft.maxSameDirection;
      g_effMaxTradesPerDay    = g_draft.maxTradesPerDay;
      g_effMaxDailyLossPct    = g_draft.maxDailyLossPct;
      g_effMaxWeeklyLossPct   = g_draft.maxWeeklyLossPct;
      g_dashDirty = false;
      Log("Paramètres de risque appliqués depuis le dashboard");
      if(loosened && g_entriesArmed) {
         g_entriesArmed = false;
         Print("BLACKHIPPO : limites de risque assouplies -> entrées désarmées, un nouvel ARMEMENT explicite est requis.");
      }
      WriteConfigSnapshot();
      DashboardRefresh();
      return;
   }

   // Annuler
   if(sparam == DashObj("BTN_CANCEL")) {
      DashDraftLoadFromEffective();
      g_dashDirty = false;
      Log("Modifications annulées");
      DashboardRefresh();
      return;
   }
}

//======================== QUICK CONFIG / PREFLIGHT ========================
// Read-only startup diagnostic for novice users. It never sends orders,
// changes inputs, or silently enables automated trading.
string JsonEscape(const string value) {
   string out="";
   for(int i=0; i<StringLen(value); i++) {
      string ch=StringSubstr(value,i,1);
      ushort code=(ushort)StringGetCharacter(value,i);
      if(code==34) out+="\\\"";
      else if(code==92) out+="\\\\";
      else if(code==10) out+="\\n";
      else if(code==13) out+="\\r";
      else if(code==9) out+="\\t";
      else out+=ch;
   }
   return(out);
}

uint AccountScopeHash() {
   string scope=IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"|"+AccountInfoString(ACCOUNT_SERVER);
   uint h=2166136261;
   for(int i=0; i<StringLen(scope); i++) { h^=(uchar)StringGetCharacter(scope,i); h*=16777619; }
   return(h);
}

string ConfigSnapshotName() {
   // Hash the account scope; never put the raw account login in the filename.
   return("CLY_MO_Pro_Config_"+IntegerToString((long)AccountScopeHash())+"_"+IntegerToString((long)InpMagic)+".json");
}

void WriteConfigSnapshot() {
   if(!InpEnableConfigBridge || MQLInfoInteger(MQL_TESTER)) return;
   string symbols="[";
   for(int i=0; i<g_n; i++) {
      if(i>0) symbols+=",";
      symbols+="\""+JsonEscape(g_s[i].name)+"\"";
   }
   symbols+="]";
   string json="{\n";
   json+="  \"schema_version\": 1,\n";
   json+="  \"ea_version\": \"BlackHippo Buffalo-Pelerin\",\n";
   json+="  \"profile\": \""+JsonEscape(RiskProfileName())+"\",\n";
   json+="  \"entries_armed\": "+(g_entriesArmed?"true":"false")+",\n";
   json+="  \"broker_company\": \""+JsonEscape(AccountInfoString(ACCOUNT_COMPANY))+"\",\n";
   json+="  \"broker_server\": \""+JsonEscape(AccountInfoString(ACCOUNT_SERVER))+"\",\n";
   json+="  \"account_currency\": \""+JsonEscape(AccountInfoString(ACCOUNT_CURRENCY))+"\",\n";
   json+="  \"account_margin_mode\": \""+(IsHedgingAccount()?"HEDGING":"NETTING")+"\",\n";
   json+="  \"leverage\": "+IntegerToString((int)AccountInfoInteger(ACCOUNT_LEVERAGE))+",\n";
   json+="  \"equity\": "+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+",\n";
   json+="  \"risk_profile_multiplier\": "+DoubleToString(ProfileRiskMultiplier(),2)+",\n";
   json+="  \"risk_per_trade_cap_pct\": "+DoubleToString(EffectiveRiskPerTradePct(),4)+",\n";
   json+="  \"portfolio_risk_cap_pct\": "+DoubleToString(EffectiveTotalRiskPct(),4)+",\n";
   json+="  \"open_risk_money\": "+DoubleToString(OpenRiskTotal(),2)+",\n";
   json+="  \"symbols\": "+symbols+",\n";
   json+="  \"server_time\": \""+TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS)+"\"\n";
   json+="}\n";
   int fh=FileOpen(ConfigSnapshotName(),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,'\t',CP_UTF8);
   if(fh==INVALID_HANDLE) {
      g_lastConfigExport=TimeCurrent(); // éviter de répéter le même avertissement chaque seconde
      Print("BLACKHIPPO BUFFALO-PELERIN: export configuration impossible, erreur=",GetLastError());
      return;
   }
   FileWriteString(fh,json);
   FileClose(fh);
   g_lastConfigExport=TimeCurrent();
}

bool QuickConfigCanArm(string &reason) {
   reason = "";
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { reason="terminal non connecté au courtier"; return(false); }
   if(!TradingAllowed()) { reason="autorisation de trading algorithmique absente"; return(false); }
   if(g_halted) { reason="halte de sécurité active; examiner le motif avant toute réactivation"; return(false); }
   if(g_n <= 0) { reason="aucun symbole exploitable"; return(false); }
   if(AccountInfoDouble(ACCOUNT_EQUITY) <= 0) { reason="equity invalide"; return(false); }
   if((InpUseCalendarFile || InpUseNativeCalendar || InpUseCalendarWebRequest) &&
      InpFailClosedCalendar && !g_newsOK) { reason="calendrier économique requis mais indisponible/non validé"; return(false); }
   if(EffectiveRiskPerTradePct() <= 0 || EffectiveTotalRiskPct() <= 0) {
      reason="plafonds de risque effectifs nuls"; return(false);
   }
   double portfolioCap = AccountInfoDouble(ACCOUNT_EQUITY) * EffectiveTotalRiskPct() / 100.0;
   if(portfolioCap <= 0 || OpenRiskTotal() >= portfolioCap) {
      reason="risque ouvert du portefeuille déjà au plafond"; return(false);
   }
   // A managed position without a valid protective stop blocks new entries.
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double bid=SymbolInfoDouble(sym,SYMBOL_BID);
      double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      if(open<=0 || sl<=0 || bid<=0 || ask<=0 || (buy && sl>=bid) || (!buy && sl<=ask)) {
         reason="position CLY.MO sans Stop Loss valide du bon côté du marché sur "+sym; return(false);
      }
   }
   return(true);
}

void QuickConfigPreflight() {
   bool hardBlock = false;
   bool warning = false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * MathMin(g_effRiskPercent * ProfileRiskMultiplier(), EffectiveRiskPerTradePct()) / 100.0;
   bool connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   bool terminalAllowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool expertAllowed = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool accountAllowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
                         (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);

   Print("============================================================");
   Print("CLY.MO PRO QUICK CONFIG — DIAGNOSTIC DE DÉMARRAGE");
   Print("Profil risque: ", RiskProfileName(),
         " | multiplicateur de profil: x", DoubleToString(ProfileRiskMultiplier(),2),
         " | Univers: ", (InpTradeOnlyCurrent ? "symbole du graphique" : "liste multi-symboles"),
         " | Symboles chargés: ", g_n);
   Print("Risque théorique par trade: ", DoubleToString(InpRiskPercent,2),
         "% | estimation actuelle: ", DoubleToString(riskMoney,2),
         " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("Compte: ", (IsHedgingAccount() ? "HEDGING" : "NETTING"),
         " | Equity: ", DoubleToString(equity,2),
         " | Marge libre: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2),
         " | Levier: 1:", (int)AccountInfoInteger(ACCOUNT_LEVERAGE));
   Print("Courtier: ", AccountInfoString(ACCOUNT_COMPANY),
         " | Serveur: ", AccountInfoString(ACCOUNT_SERVER),
         " | Devise: ", AccountInfoString(ACCOUNT_CURRENCY),
         " | Nouvelles entrées: ", (g_entriesArmed ? "ARMEES" : "DESARMEES"));

   if(!connected) { Print("[BLOQUANT] Terminal non connecté au serveur du courtier."); hardBlock=true; }
   if(!terminalAllowed || !expertAllowed || !accountAllowed) {
      Print("[BLOQUANT] Trading algorithmique non autorisé par le terminal, l'EA ou le compte.");
      hardBlock=true;
   }
   if(g_n <= 0) { Print("[BLOQUANT] Aucun symbole exploitable."); hardBlock=true; }

   for(int i=0; i<g_n; i++) {
      string sym=g_s[i].name;
      MqlTick tick;
      double point=SymbolInfoDouble(sym,SYMBOL_POINT);
      double tickSize=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
      double vstep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
      long tradeMode=SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);
      bool quoteOK=SymbolInfoTick(sym,tick) && tick.bid>0 && tick.ask>0 && tick.time>0;
      string status="OK";
      if(tradeMode==SYMBOL_TRADE_MODE_DISABLED || tradeMode==SYMBOL_TRADE_MODE_CLOSEONLY) {
         status="BLOQUÉ: symbole non ouvert aux nouvelles entrées";
         warning=true;
      } else if(point<=0 || tickSize<=0 || vmin<=0 || vstep<=0) {
         status="BLOQUÉ: métadonnées de négociation incomplètes";
         warning=true;
      } else if(!quoteOK) {
         status="ATTENTION: cotation indisponible (marché fermé ou flux absent)";
         warning=true;
      } else {
         double spreadPts=(tick.ask-tick.bid)/point;
         int age=(int)MathMax(0,TimeCurrent()-tick.time);
         if(age>InpMaxQuoteAgeSec) {
            status="ATTENTION: cotation ancienne, "+IntegerToString(age)+"s";
            warning=true;
         } else if(spreadPts>InpMaxSpreadPoints) {
            status="ATTENTION: spread actuel élevé ("+DoubleToString(spreadPts,1)+" points)";
            warning=true;
         }
      }
      Print("[",sym,"] ",status);
   }

   if((InpUseCalendarFile || InpUseNativeCalendar || InpUseCalendarWebRequest) && !g_newsOK) {
      Print("[ATTENTION] Calendrier économique demandé mais aucune donnée valide chargée. Politique fail-closed: ",
            (InpFailClosedCalendar ? "OUI — nouvelles entrées bloquées" : "NON — vérifier le risque de news"));
      warning=true;
   }
   if(InpTradeOnlyCurrent && InpAutoScanMarketWatch)
      Print("[INFO] Le scan Market Watch est ignoré car le mode symbole du graphique est prioritaire.");
   if(InpSpreadPctileMax > 0.0)
      Print("[INFO] Filtre percentile du spread actif: seuil historique M1 au percentile ",
            DoubleToString(InpSpreadPctileMax * 100.0, 0),
            " (120 barres clôturées; repli sur les limites absolues si historique insuffisant).");

   if(hardBlock) Print("RÉSULTAT QUICK CONFIG: NON PRÊT — corriger les éléments BLOQUANTS avant toute entrée.");
   else if(warning) Print("RÉSULTAT QUICK CONFIG: À VÉRIFIER — le robot reste soumis aux filtres d'exécution.");
   else Print("RÉSULTAT QUICK CONFIG: CONTRÔLES INITIAUX OK — cela ne certifie ni la stratégie ni la rentabilité.");
   Print("Mode conseillé: DÉMO jusqu'à validation MetaEditor, backtests et tests chez le courtier.");
   Print("============================================================");
}

void Engine() {
   static uint lastRun = 0;
   if(!MQLInfoInteger(MQL_TESTER)) {
      uint now = GetTickCount();
      if(now - lastRun < 250) return;
      lastRun = now;
   }
   MonitorHealth();
   DashboardRefreshThrottled();
   if(InpEnableConfigBridge && !MQLInfoInteger(MQL_TESTER) &&
      (g_lastConfigExport==0 || TimeCurrent()-g_lastConfigExport>=5)) WriteConfigSnapshot();
   NewDayCheck();
   bool guardOK = DailyGuard();

   ManagePositions();

   // Maintenance exécutée AVANT la sortie de fin de session : calendrier, état persistant,
   // nettoyage et journal des rejets ne sont plus suspendus entre l'heure de clôture et minuit.
   bool calSources = (InpUseCalendarFile || InpUseNativeCalendar || InpUseCalendarWebRequest);
   if(!MQLInfoInteger(MQL_TESTER) && calSources) {
      int calEvery = (InpUseCalendarWebRequest ? MathMax(60, InpCalendarRefreshSec) : 600);
      if(!g_newsOK) calEvery = MathMin(calEvery, 60);   // source non valide : nouvel essai rapide
      if(TimeCurrent() - g_lastCalLoad >= calEvery) {
         bool refreshed=false;
         if(InpUseNativeCalendar) refreshed=LoadNativeCalendar();
         if(!refreshed && InpUseCalendarWebRequest) {
            if(DownloadCalendarWeb()) { LoadCalendar(); refreshed=g_newsOK; }
         }
         if(!refreshed && (InpUseCalendarFile || InpUseCalendarWebRequest)) LoadCalendar();
      }
   }
   if(TimeCurrent() - g_lastSave > 60) SaveState();
   if(!MQLInfoInteger(MQL_TESTER) && TimeCurrent() - g_lastCleanup > 3600) CleanupGVs();
   LogRejSummary();

   if(IsCloseTime()) { CloseAll("fin de session"); return; }

   if(!guardOK || g_halted) return;
   if(!g_entriesArmed) return; // fail-safe: gérer les positions, mais aucune nouvelle entrée
   if(TimeCurrent() < g_pauseUntil) return;
   if(!TradingAllowed() || !InTradingWindow() || InNewsWindow()) return;

   ProcessPullbackRecoveries();
   for(int i = 0; i < g_n; i++) EvaluateEntry(g_s[i]);
   ProcessCandidates();
}

//======================== INIT / DEINIT ========================
bool Bad(const string msg) { Print("CLYMO: paramètre invalide - ", msg); return(false); }

bool ValidateInputs() {
   if(InpRequireManualArm && !InpShowDashboard && !MQLInfoInteger(MQL_TESTER)) return Bad("ManualArm nécessite le tableau de bord activé");
   if(InpRiskProfile != CLY_RISK_SAFE && InpRiskProfile != CLY_RISK_BALANCED &&
      InpRiskProfile != CLY_RISK_DYNAMIC && InpRiskProfile != CLY_RISK_CUSTOM) return Bad("RiskProfile");
   if(InpMaxAutoSymbols < 1 || InpMaxAutoSymbols > 100) return Bad("MaxAutoSymbols 1..100");
   if(InpHealthIntervalSec < 10 || InpHealthMaxQuoteAgeSec < 10) return Bad("paramètres HealthMonitor");
   if(InpMagic < 0) return Bad("Magic");
   if(!InpTradeOnlyCurrent && StringLen(InpSymbols) == 0) return Bad("Symbols");
   if(InpRiskPercent <= 0 || InpRiskPercent > InpMaxRiskPerTrade ||
      InpMaxRiskPerTrade > 10.0 || InpMaxTotalRiskPct < InpMaxRiskPerTrade ||
      InpMaxTotalRiskPct > 20.0) return Bad("RiskPercent / MaxRiskPerTrade / MaxTotalRiskPct");
   if(InpMaxCurrencyRiskPct <= 0 || InpMaxCurrencyRiskPct > 20.0) return Bad("MaxCurrencyRiskPct");
   if(InpMaxOpenTrades < 1 || InpMaxSameDirection < 1)
      return Bad("MaxOpenTrades / MaxSameDirection");
   if(InpMaxMarginUsePct <= 0 || InpMaxMarginUsePct > 100) return Bad("MaxMarginUsePct");
   if(InpMaxDailyLossPct < 0 || InpDailyProfitTargetPct < 0 || InpMaxTradesPerDay < 0 ||
      InpMaxTradesPerSymbol < 0 || InpMaxConsecLosses < 0 || InpPauseMinutes < 0) return Bad("limites journalières");
   if(InpMaxWeeklyLossPct < 0 || (InpMaxWeeklyLossPct > 0 && InpMaxDailyLossPct > 0 && InpMaxWeeklyLossPct < InpMaxDailyLossPct))
      return Bad("MaxWeeklyLossPct (doit être >= MaxDailyLossPct)");
   if(InpTesterMinTrades < 1 || InpTesterMaxDDPct <= 0) return Bad("paramètres OnTester");
   if(InpDDFullPct <= InpDDStartPct || InpDDFloorMult <= 0 || InpDDFloorMult > 1) return Bad("DD scaling");
   if(InpRollTrades < 1 || InpPFLow < 0 || InpPFGood <= InpPFLow ||
      InpPFLowMult <= 0 || InpPFLowMult > 1 || InpPFGoodMult < 1) return Bad("profit factor glissant");
   if(InpRiskMultStrong <= 0 || InpRiskMultNormal <= 0) return Bad("RiskMult");
   if(InpCommissionPerLot < 0 || InpCommissionPerLot > 1000000) return Bad("CommissionPerLot");
   if(InpRiskMultFloor < 0 || InpRiskMultFloor > 1 ||
      InpRiskMultStrong <= 0 || InpRiskMultStrong > 3 ||
      InpRiskMultNormal <= 0 || InpRiskMultNormal > 3) return Bad("multiplicateurs de risque");
   if(InpMaxBadFills < 0 || InpMaxBadFills > 100 ||
      InpPostFillRiskTolPct > 100 || InpMaxFillDevATR > 5.0) return Bad("limites de remplissage");
   if(InpMaxQuoteAgeSec > 3600 || InpUncertainLockMin > 1440 ||
      InpMaxRetries > 10 || InpRetryDelayMs > 5000) return Bad("paramètres d'exécution");
   if(InpMaxSpreadPoints < 1 || InpMaxSpreadPoints > 100000 ||
      InpMaxSpreadATRFrac <= 0 || InpMaxSpreadATRFrac > 1) return Bad("limites de spread");
   if(InpMinADXRise < -100 || InpMinADXRise > 100 ||
      InpADXStrong > 100 || InpADXMin > 100) return Bad("seuils ADX");
   if(InpMaxConsecLosses > 100 || InpMaxTradesPerDay > 1000 ||
      InpMaxTradesPerSymbol > 1000) return Bad("limites de fréquence");
   if(InpSkipOpenMin < 0 || InpSkipOpenMin > 180) return Bad("SkipOpenMin");
   if(InpEntryTF == PERIOD_CURRENT || InpConfirmTF == PERIOD_CURRENT || InpHigherTF == PERIOD_CURRENT)
      return Bad("timeframes explicites requis");
   if(InpEMAFast >= InpEMASlow || InpEMASlow >= InpEMATrend) return Bad("ordre des EMA");
   if(InpRSIPeriod < 2 || InpADXPeriod < 2 || InpATRPeriod < 2 || InpERLookback < 2 ||
      InpATRRefPeriod < InpATRPeriod) return Bad("périodes d'indicateurs");
   if(InpRSIPullBuy < 0 || InpRSIPullBuy > 100 || InpRSIPullSell < 0 || InpRSIPullSell > 100) return Bad("RSI pull");
   if(InpADXMin < 0 || InpADXStrong < InpADXMin) return Bad("ADX");
   if(InpMinER < 0 || InpMinER > 1 || InpStrongER < InpMinER) return Bad("ER");
   if(InpScoreBaseThreshold < 50 || InpScoreBaseThreshold > 95 ||
      InpScoreStrongDiscount < 0 || InpScoreStrongDiscount > 15 ||
      InpScoreChopPenalty < 0 || InpScoreChopPenalty > 20 ||
      InpScoreVolumeLookback < 5 || InpScoreVolumeLookback > 200 ||
      InpScoreStructureBars < 3 || InpScoreStructureBars > 50) return Bad("score adaptatif");
   if(InpHardATRRatioMult < 1.0 || InpHardATRRatioMult > 3.0 || InpHardCandleMult < 1.0 || InpHardCandleMult > 3.0 ||
      InpHardExtensionMult < 1.0 || InpHardExtensionMult > 3.0) return Bad("multiplicateurs de rejet dur (1.0 .. 3.0)");
   if(InpEnableDiagnosticLog && StringLen(InpDiagnosticFile) < 5) return Bad("InpDiagnosticFile");
   if(!InpUsePullbackSetup && !InpUseBreakoutSetup) return Bad("au moins un setup (Pullback/Breakout) doit être actif");
   if(InpMinSetupPoints < 0 || InpMinSetupPoints > 30 ||
      InpHardADXFloorFrac < 0 || InpHardADXFloorFrac > 1 ||
      InpHardERFloorFrac < 0 || InpHardERFloorFrac > 1) return Bad("garde-fous / points de setup");
   if(InpMRBandsPeriod < 5 || InpMRBandsPeriod > 200 || InpMRBandsDeviation <= 0 ||
      InpMRRSIBuy < 0 || InpMRRSIBuy > 50 || InpMRRSISell < 50 || InpMRRSISell > 100 ||
      InpMRADXMax <= 0 || InpMRERMax < 0 || InpMRERMax > 1 ||
      InpMRRiskMult <= 0 || InpMRRiskMult > 1 || InpMRMinBandWidthATR < 0)
      return Bad("paramètres Mean Reversion");
   if(InpMaxATRRatio <= 0 || InpHighVolRatio <= 0 || InpHighVolRatio > InpMaxATRRatio) return Bad("ratios ATR");
   if(InpHighVolRiskCut <= 0 || InpHighVolRiskCut > 1) return Bad("HighVolRiskCut");
   if(InpMinEMASepATR < 0 || InpMaxSignalCandleATR <= 0 || InpMinBodyRatio < 0 || InpMinBodyRatio > 1 ||
      InpMaxExtensionATR <= 0) return Bad("qualité de bougie");
   if(InpStructBars < 2 || InpStructBufATR < 0 || InpMinStructATR <= 0 || InpMaxStructATR <= InpMinStructATR) return Bad("SL structurel");
   if(InpRRBase <= 0 || InpRRStrong < InpRRBase) return Bad("RR");
   if(InpMaxCostToTP <= 0 || InpMaxCostToTP >= 1) return Bad("MaxCostToTP");
   if(InpMaxSpreadPoints <= 0 || InpMaxSpreadATRFrac <= 0) return Bad("spread");
   if(InpExtraStopBufPts < 0) return Bad("ExtraStopBufPts");
   if(InpMRScoreThreshold < 30 || InpMRScoreThreshold > 95 || InpMRMinRR <= 0 || InpMRH1FlatATR < 0 ||
      InpMRMaxHoldBars < 1 || InpMRBETriggerR < 0 || InpMRMaxCostToTP <= 0 || InpMRMaxCostToTP >= 1 ||
      InpMRVolSpikeMult < 0.5 || InpMRVolSpikeMult > 5.0)
      return Bad("Mean Reversion (sorties)");
   if(InpHighVolATRRatio < 1.0 || InpTrendADXFloor < 10 || InpRangeADXCeil > InpTrendADXFloor ||
      InpRegimeRiskTrend <= 0 || InpRegimeRiskRange <= 0 || InpRegimeRiskHighVol <= 0 || InpRegimeRiskTrans <= 0 ||
      InpDailyRiskBudgetPct <= 0 || InpVolTargetFloor <= 0 || InpVolTargetFloor > 1 || InpVolTargetCeil < InpVolTargetFloor)
      return Bad("Régimes / Vol Targeting");
   if(InpRankWaitSec < 0 || InpRankWaitSec >= InpEntryWindowSec || InpCooldownExitBars < 0 || InpCooldownLossBars < 0 ||
      InpNewsExitMin < 0 || InpRiskMultFloor < 0 || InpRiskMultFloor > 1 || InpPFMinTrades < 3 ||
      InpScratchFrac < 0 || InpScratchFrac > 1 || InpMaxBadFills < 0 ||
      InpMinScoreMargin < 0 || InpSpreadPctileMax < 0 || InpSpreadPctileMax > 1 ||
      InpMaxCorrelation < 0.0 || InpMaxCorrelation > 1.0)
      return Bad("sélection / cooldown / news / risque / corrélation");
   if(InpEMAFast < 1 || InpEMAConfirm < 1 || InpEMAH1 < 1) return Bad("périodes EMA");
   if(InpPartialPct <= 0 || InpPartialPct >= 100 || InpPartialR <= 0) return Bad("partiel");
   if(InpBETriggerR <= 0 || InpBEOffsetPoints < 0) return Bad("break-even");
   if(InpTrailStartR <= 0 || InpTrailATR <= 0 || InpTrailStrongMult <= 0) return Bad("trailing");
   if(InpMaxHoldBars < 1 || InpMaxHoldBars > 10000 ||
      InpTimeStopMinR < -5 || InpTimeStopMinR > 20 ||
      InpMRMaxHoldBars > 10000) return Bad("time-stop");
   if(InpStartHour < 0 || InpStartHour > 23 || InpEndHour < 1 || InpEndHour > 24 || InpEndHour <= InpStartHour ||
      InpFridayEndHour < 1 || InpFridayEndHour > 24) return Bad("horaires d'entrée");
   if(InpCloseHour < 0 || InpCloseHour > 23 || InpCloseMinute < 0 || InpCloseMinute > 59 ||
      InpFridayCloseHour < 0 || InpFridayCloseHour > 23 || InpFridayCloseMinute < 0 || InpFridayCloseMinute > 59)
      return Bad("horaires de clôture");
   if(InpCloseHour * 60 + InpCloseMinute < InpEndHour * 60 ||
      InpFridayCloseHour * 60 + InpFridayCloseMinute < InpFridayEndHour * 60)
      return Bad("clôture avant la dernière entrée");
   if(InpStartHour * 60 + InpSkipOpenMin >= InpEndHour * 60 ||
      InpStartHour * 60 + InpSkipOpenMin >= InpFridayEndHour * 60) return Bad("fenêtre horaire vide après SkipOpenMin");
   if(InpNewsBufferMin < 0 || InpCalMinBefore < 0 || InpCalMinAfter < 0 || InpCalendarMaxAgeH < 1 ||
      InpCalMinImpact < 0 || InpCalMinImpact > 3) return Bad("news / calendrier");
   if(InpCalendarRefreshSec < 60 || InpCalendarTimeoutMs < 500 || InpCalendarTimeoutMs > 30000)
      return Bad("intervalle / timeout WebRequest calendrier");
   if(InpUseCalendarWebRequest && (StringFind(InpCalendarURL, "https://") != 0))
      return Bad("InpCalendarURL doit être une URL HTTPS directe vers un CSV brut");
   if((InpUseNativeCalendar || InpUseCalendarWebRequest) && MQLInfoInteger(MQL_TESTER) && !InpUseCalendarFile)
      Print("CLYMO: en backtest, fournir un CSV historique; le calendrier natif/WebRequest n'est pas disponible.");
   if(InpMaxRetries < 1 || InpRetryDelayMs < 0) return Bad("retries");
   if(InpBaseDeviation < 0 || InpMaxDeviation < InpBaseDeviation || InpDevATRMult < 0 || InpMaxFillDevATR <= 0)
      return Bad("déviation");
   if(InpMaxQuoteAgeSec < 1 || InpUncertainLockMin < 1 || InpPostFillRiskTolPct < 0 || InpCooldownBars < 0)
      return Bad("sécurité d'exécution");
   if(InpMaxEntryDistanceATR <= 0.0 || InpMaxEntryDistanceATR > 2.0 ||
      InpMaxCandidateATRChange < 0.0 || InpMaxCandidateATRChange > 1.0 ||
      InpAdaptiveMaxDistanceATR < InpMaxEntryDistanceATR || InpAdaptiveMaxDistanceATR > 2.0 ||
      InpAdaptiveMinADX < 0.0 || InpAdaptiveMinADX > 100.0 ||
      InpAdaptiveMinER < 0.0 || InpAdaptiveMinER > 1.0 ||
      InpAdaptiveMinScoreMargin < 0.0 || InpAdaptiveMinScoreMargin > 100.0 ||
      InpChaseRiskReduction < 0.0 || InpChaseRiskReduction > 1.0 ||
      InpPullbackWatchMaxATR < InpMaxEntryDistanceATR || InpPullbackWatchMaxATR > 2.0 ||
      InpPullbackMinRetraceATR <= 0.0 || InpPullbackMinRetraceATR > 0.75)
      return Bad("confirmation finale / anti-poursuite adaptatif");
   if(InpProfitLockTriggerR < 0.0 || InpProfitLockR < 0.0 ||
      InpProfitLockR > InpProfitLockTriggerR || InpProfitLockR > 5.0)
      return Bad("verrouillage progressif des gains");
   if(InpEntryWindowSec < 1 || InpEntryWindowSec >= PeriodSeconds(InpEntryTF)) return Bad("EntryWindowSec");
   if(PeriodSeconds(InpConfirmTF) < PeriodSeconds(InpEntryTF) ||
      PeriodSeconds(InpHigherTF) < PeriodSeconds(InpConfirmTF)) return Bad("hiérarchie TF (Entry <= Confirm <= Higher)");
   return(true);
}

int OnInit() {
   if(!ValidateInputs()) return(INIT_PARAMETERS_INCORRECT);
   g_activeRiskProfile = InpRiskProfile;
   InitEffectiveRiskParams();
   if(!MQLInfoInteger(MQL_TESTER) && InpRememberRiskProfile && !InpForceInputProfile && GlobalVariableCheck(K("risk_profile"))) {
      int savedProfile=(int)GlobalVariableGet(K("risk_profile"));
      if(savedProfile==CLY_RISK_SAFE || savedProfile==CLY_RISK_BALANCED ||
         savedProfile==CLY_RISK_DYNAMIC || savedProfile==CLY_RISK_CUSTOM) {
         if(savedProfile != (int)InpRiskProfile)
            Print("BLACKHIPPO ATTENTION : le profil mémorisé (", savedProfile, ") remplace l'input InpRiskProfile (",
                  (int)InpRiskProfile, "). Mettre InpForceInputProfile=true pour imposer l'input.");
         g_activeRiskProfile=(CLY_RISK_PROFILE)savedProfile;
      }
      else Print("BLACKHIPPO BUFFALO-PELERIN: profil mémorisé invalide, profil input utilisé.");
   }
   if(!MQLInfoInteger(MQL_TESTER) && InpRememberRiskProfile && InpForceInputProfile)
      GlobalVariableSet(K("risk_profile"), (double)g_activeRiskProfile);
   g_entriesArmed = (bool)MQLInfoInteger(MQL_TESTER); // testeur : conserver les backtests automatisés

   if(MQLInfoInteger(MQL_TESTER)) GlobalVariablesDeleteAll(K(""));

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetAsyncMode(false);

   string list[];
   bool autoDiscovered=false;
   int cnt = InpTradeOnlyCurrent ? 0 : StringSplit(InpSymbols, ',', list);
   if(InpTradeOnlyCurrent) { ArrayResize(list, 1); list[0] = _Symbol; cnt = 1; }
   // Auto-discovery: live Market Watch only. Strategy Tester keeps an explicit,
   // reproducible symbol list to avoid nondeterministic optimization universes.
   if(!InpTradeOnlyCurrent && InpAutoScanMarketWatch && !MQLInfoInteger(MQL_TESTER)) {
      ArrayResize(list,0); cnt=0; autoDiscovered=true;
      int total=SymbolsTotal(true);
      for(int si=0; si<total && cnt<InpMaxAutoSymbols; si++) {
         string candidate=SymbolName(si,true);
         if(candidate=="") continue;
         string bc=SymbolInfoString(candidate,SYMBOL_CURRENCY_BASE);
         string qc=SymbolInfoString(candidate,SYMBOL_CURRENCY_PROFIT);
         if(StringLen(bc)!=3 || StringLen(qc)!=3 || bc==qc) continue;
         long tm=SymbolInfoInteger(candidate,SYMBOL_TRADE_MODE);
         long calcMode=SymbolInfoInteger(candidate,SYMBOL_TRADE_CALC_MODE);
         // Ne pas confondre une paire Forex avec un CFD/métal ayant deux codes devise de 3 lettres.
         if(calcMode!=SYMBOL_CALC_MODE_FOREX && calcMode!=SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) continue;
         if(tm==SYMBOL_TRADE_MODE_DISABLED || tm==SYMBOL_TRADE_MODE_CLOSEONLY) continue;
         ArrayResize(list,cnt+1); list[cnt]=candidate; cnt++;
      }
      if(cnt==0) { cnt=StringSplit(InpSymbols,',',list); Print("AutoScanner: aucun Forex détecté; retour à InpSymbols."); }
      else Print("AutoScanner: ",cnt," symboles Forex Market Watch détectés.");
   }
   ArrayResize(g_s, 0);
   g_n = 0;
   for(int i = 0; i < cnt; i++) {
      string sym = list[i];
      StringTrimLeft(sym); StringTrimRight(sym);
      if(sym == "") continue;
      if(!InpTradeOnlyCurrent && !autoDiscovered) sym += InpSymbolSuffix;
      if(!SymbolSelect(sym, true)) { Print("Symbole indisponible: ", sym); continue; }
      if(SymIndex(sym) >= 0) continue;
      long tradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
      double pointSize = SymbolInfoDouble(sym, SYMBOL_POINT);
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double volumeMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double volumeStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double volumeMax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      if(pointSize <= 0 || tickSize <= 0 || volumeMin <= 0 || volumeStep <= 0 ||
         volumeMax < volumeMin || tradeMode == SYMBOL_TRADE_MODE_DISABLED) {
         Print("Symbole ignoré: métadonnées de trading invalides pour ", sym);
         continue;
      }
      int k = g_n;
      ArrayResize(g_s, k + 1);
      g_s[k].name = sym;
      g_s[k].hEmaF = iMA(sym, InpEntryTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
      g_s[k].hEmaS = iMA(sym, InpEntryTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
      g_s[k].hEmaT = iMA(sym, InpEntryTF, InpEMATrend, 0, MODE_EMA, PRICE_CLOSE);
      g_s[k].hRsi  = iRSI(sym, InpEntryTF, InpRSIPeriod, PRICE_CLOSE);
      g_s[k].hAdx  = iADX(sym, InpEntryTF, InpADXPeriod);
      g_s[k].hAtr  = iATR(sym, InpEntryTF, InpATRPeriod);
      g_s[k].hAtrRef = iATR(sym, InpEntryTF, InpATRRefPeriod);
      g_s[k].hH1   = iMA(sym, InpHigherTF, InpEMAH1, 0, MODE_EMA, PRICE_CLOSE);
      g_s[k].hM15  = iMA(sym, InpConfirmTF, InpEMAConfirm, 0, MODE_EMA, PRICE_CLOSE);
      if(g_s[k].hEmaF == INVALID_HANDLE || g_s[k].hEmaS == INVALID_HANDLE || g_s[k].hEmaT == INVALID_HANDLE ||
         g_s[k].hRsi == INVALID_HANDLE || g_s[k].hAdx == INVALID_HANDLE || g_s[k].hAtr == INVALID_HANDLE ||
         g_s[k].hAtrRef == INVALID_HANDLE || g_s[k].hH1 == INVALID_HANDLE || g_s[k].hM15 == INVALID_HANDLE) {
         Print("Handles d'indicateurs invalides pour ", sym);
         int bad[9];
         bad[0]=g_s[k].hEmaF; bad[1]=g_s[k].hEmaS; bad[2]=g_s[k].hEmaT; bad[3]=g_s[k].hRsi; bad[4]=g_s[k].hAdx;
         bad[5]=g_s[k].hAtr; bad[6]=g_s[k].hAtrRef; bad[7]=g_s[k].hH1; bad[8]=g_s[k].hM15;
         for(int z=0; z<9; z++) if(bad[z] != INVALID_HANDLE) IndicatorRelease(bad[z]);
         continue;
      }
      g_s[k].lastBar = 0; g_s[k].lastEntryBar = 0; g_s[k].lockUntil = 0; g_s[k].done = false;
      g_s[k].tradesToday = 0;
      g_s[k].lastExit = 0; g_s[k].lastExitLoss = false; g_s[k].rejBar = 0;
      g_s[k].digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      g_s[k].point = SymbolInfoDouble(sym, SYMBOL_POINT);
      g_s[k].base = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
      g_s[k].quote = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
      g_n++;
   }
   ArrayResize(g_s, g_n);
   if(g_n == 0) { Print("Aucun symbole exploitable"); return(INIT_FAILED); }

   ParseNewsDays(InpNewsDays);
   ParseWindows(InpNewsWindows);
   if(InpUseNativeCalendar && !MQLInfoInteger(MQL_TESTER)) LoadNativeCalendar();
   if((!g_newsOK || MQLInfoInteger(MQL_TESTER)) &&
      (InpUseCalendarFile || (MQLInfoInteger(MQL_TESTER) && InpUseCalendarWebRequest))) {
      LoadCalendar();
   }
   if(!MQLInfoInteger(MQL_TESTER) && !g_newsOK && InpUseCalendarWebRequest) {
      DownloadCalendarWeb();
      LoadCalendar();
   }

   if(!MQLInfoInteger(MQL_TESTER)) LoadState();
   else {
      g_day = DayStart(TimeCurrent()); g_dayEquity = AccountInfoDouble(ACCOUNT_EQUITY); g_peak = g_dayEquity;
      g_week = WeekStart(TimeCurrent()); g_weekEquity = g_dayEquity; g_halted = false; g_haltKind = HALT_NONE;
   }
   if(InpResetCriticalHalt && g_haltKind == HALT_CRITICAL) { g_halted = false; g_haltKind = HALT_NONE; Log("Halte critique levée (InpResetCriticalHalt)"); }
   if(g_halted) Print("BLACKHIPPO: démarrage en HALTE (type ", g_haltKind, ").");
   Log("Heure serveur=" + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + " | GMT=" +
       TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES) + " | vérifier que les horaires d'entrée/clôture correspondent à cette heure serveur");
   if(MQLInfoInteger(MQL_TESTER) && !g_newsOK)
      Print("BLACKHIPPO: ATTENTION - backtest SANS filtre news (aucun CSV historique valide) : résultats optimistes vs live.");
   ArrayResize(g_cand, 0);
   RebuildStats();
   CleanupGVs();
   SaveState();

   if(IsHedgingAccount())
      Log("Mode HEDGING détecté : gestion par ticket et réduction partielle dédiée.");
   else
      Log("Mode NETTING détecté : toute position préexistante sur un symbole géré bloque une nouvelle entrée. Ne pas partager ces symboles avec une autre stratégie.");

   QuickConfigPreflight();
   if(!MQLInfoInteger(MQL_TESTER) && !InpRequireManualArm) {
      string armReason="";
      if(QuickConfigCanArm(armReason)) g_entriesArmed=true;
      else Print("BLACKHIPPO BUFFALO-PELERIN: armement automatique refusé: ",armReason);
   }
   DashboardRefresh();
   WriteConfigSnapshot();
   WriteDiagnosticEvent("EA_INIT","","BlackHippo Buffalo-Pelerin démarré",AccountInfoDouble(ACCOUNT_EQUITY));
   EventSetTimer(1);
   Log("Init OK | symboles=" + IntegerToString(g_n) + " | TF=" + EnumToString(InpEntryTF));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   WriteDiagnosticEvent("EA_DEINIT","","reason="+IntegerToString(reason),AccountInfoDouble(ACCOUNT_EQUITY));
   WriteConfigSnapshot();
   DashboardRemove();
   for(int i = 0; i < g_n; i++) {
      int hs[9];
      hs[0]=g_s[i].hEmaF; hs[1]=g_s[i].hEmaS; hs[2]=g_s[i].hEmaT; hs[3]=g_s[i].hRsi; hs[4]=g_s[i].hAdx;
      hs[5]=g_s[i].hAtr; hs[6]=g_s[i].hAtrRef; hs[7]=g_s[i].hH1; hs[8]=g_s[i].hM15;
      for(int k = 0; k < 9; k++) if(hs[k] != INVALID_HANDLE) IndicatorRelease(hs[k]);
   }
   if(!MQLInfoInteger(MQL_TESTER)) SaveState();
}

void OnTick()  { Engine(); }
void OnTimer() { Engine(); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal)) return;
   long dtype = HistoryDealGetInteger(deal, DEAL_TYPE);
   if(dtype == DEAL_TYPE_BALANCE || dtype == DEAL_TYPE_CREDIT || dtype == DEAL_TYPE_CORRECTION) {
      double amt = HistoryDealGetDouble(deal, DEAL_PROFIT);
      g_peak += amt;
      g_dayEquity += amt;
      g_weekEquity += amt;
      double eqNow = AccountInfoDouble(ACCOUNT_EQUITY);
      if(g_peak < eqNow) g_peak = eqNow;
      if(g_dayEquity <= 0) g_dayEquity = eqNow;
      if(g_weekEquity <= 0) g_weekEquity = eqNow;
      SaveState();
      Log("Opération de balance " + DoubleToString(amt, 2) + " : pic/ref. jour ajustés");
      return;
   }
   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;
   long en = HistoryDealGetInteger(deal, DEAL_ENTRY);
   ulong pid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   string sym = HistoryDealGetString(deal, DEAL_SYMBOL);
   double dealVolume=HistoryDealGetDouble(deal,DEAL_VOLUME);
   double dealPrice=HistoryDealGetDouble(deal,DEAL_PRICE);
   WriteDiagnosticEvent("DEAL_"+EnumToString((ENUM_DEAL_ENTRY)en),sym,
      "ticket="+IntegerToString((long)deal)+"; pid="+IntegerToString((long)pid)+
      "; volume="+DoubleToString(dealVolume,2)+"; price="+
      DoubleToString(dealPrice,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS)),
      HistoryDealGetDouble(deal,DEAL_PROFIT));

   if(en == DEAL_ENTRY_IN && pid > 0) {
      bool alreadyCounted = GlobalVariableCheck(KP("RM", pid));
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) != pid) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         string psym = PositionGetString(POSITION_SYMBOL);
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double vol = PositionGetDouble(POSITION_VOLUME);
         bool buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         if(alreadyCounted && sl > 0 && ((buy && sl >= open) || (!buy && sl <= open))) break;
         if(sl <= 0 || open <= 0 || vol <= 0 || (buy && sl >= open) || (!buy && sl <= open)) {
            if(!CloseRejected(tk, "remplissage tardif sans SL valide"))
               Print("CRITIQUE BLACKHIPPO: intervention manuelle requise, pid=", pid);
            break;
         }

         double risk = PosRiskMoney(psym, buy, open, sl, vol);
         double tp = PositionGetDouble(POSITION_TP);
         string lateFillReason;
         if(!PostFillRiskOK(psym, buy, open, sl, tp, vol, tk, lateFillReason)) {
            CloseRejected(tk, "remplissage tardif: " + lateFillReason);
            break;
         }

         if(!alreadyCounted) GlobalVariableSet(KP("R0", pid), MathAbs(open - sl));
         if(risk > 0) GlobalVariableSet(KP("RM", pid), risk);
         if(!alreadyCounted) {
            GlobalVariableSet(KP("AS", pid), 0.0);
            int si = SymIndex(psym);
            if(si >= 0) {
               g_tradesToday++;
               g_s[si].tradesToday++;
               g_s[si].lastEntryBar = iTime(psym, InpEntryTF, 0);
            }
            SaveState();
            Log("Ouverture tardive réconciliée " + psym + " pid=" + IntegerToString((long)pid));
         } else {
            Log("Remplissage additionnel réconcilié " + psym + " pid=" + IntegerToString((long)pid));
         }
         break;
      }
   }

   if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_OUT_BY && en != DEAL_ENTRY_INOUT) return;
   double net; bool closed;
   if(!PositionNet(pid, net, closed) || !closed) return;
   WriteDiagnosticEvent("POSITION_CLOSED",sym,
      "pid="+IntegerToString((long)pid)+"; résultat net consolidé",net);
   RegisterClosed(pid, sym, net);
}

//======================== OPTIMISATION ========================
// multi-objectif robuste — Recovery × √trades × PF capped × DD penalty × equity smoothness
// + pénalité légère pour sur-trading (trop de trades par rapport au profit).
double OnTester() {
   // Multi-objectif exigeant – Recovery × √trades × PF capped × DD penalty × equity smoothness
   // + pénalité renforcée pour sur-trading.
   double trades = TesterStatistics(STAT_TRADES);
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   double rf     = TesterStatistics(STAT_RECOVERY_FACTOR);
   double dd     = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double np     = TesterStatistics(STAT_PROFIT);
   if(trades < InpTesterMinTrades || np <= 0 || pf <= 1.05 || dd > InpTesterMaxDDPct) return(0.0);
   double base = rf * MathSqrt(trades / 120.0) * MathMin(pf - 1.0, 0.90);
   double ddPen = MathMax(0.35, 1.0 - 0.60 * dd / InpTesterMaxDDPct);
   double lr = TesterStatistics(STAT_LR_CORRELATION);
   double smooth = MathMax(0.20, MathMin(1.0, (lr + 1.0) * 0.5));   // map [-1,1] → [0,1]
   double profitPct = np / MathMax(1.0, TesterStatistics(STAT_INITIAL_DEPOSIT)) * 100.0;
   double overTradePen = 1.0;
   if(profitPct > 0.5 && trades / profitPct > 3.5)
      overTradePen = MathMax(0.50, 3.5 / (trades / profitPct));
   return(base * ddPen * smooth * overTradePen);
}
