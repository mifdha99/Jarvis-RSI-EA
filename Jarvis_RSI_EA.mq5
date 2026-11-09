#property strict
#property version "1.00"
#property description "Jarvis RSI 14 EA - tick-based threshold crossing"

#include <Trade/Trade.mqh>

input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;
input int InpRSIPeriod = 14;
input double InpOverbought = 70.0;
input double InpOversold = 30.0;
input double InpLots = 0.01;
input double InpStopLossPips = 50.0;
input double InpTakeProfitPips = 50.0;
input ulong InpMagicNumber = 14147030;
input int InpDeviationPoints = 20;

CTrade trade;
int rsiHandle = INVALID_HANDLE;
double previousRsi = EMPTY_VALUE;

double PipSize()
{
   return ((_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point);
}

double NormalizedLots()
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lots = MathMax(minLot, MathMin(maxLot, InpLots));
   if(step > 0.0)
      lots = MathFloor((lots / step) + 1e-8) * step;

   int digits = 2;
   if(step >= 1.0) digits = 0;
   else if(step >= 0.1) digits = 1;
   else if(step >= 0.01) digits = 2;
   else if(step >= 0.001) digits = 3;
   else digits = 4;

   return NormalizeDouble(lots, digits);
}

bool HasOpenPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

void OpenBuy()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double pip = PipSize();
   double sl = NormalizeDouble(tick.ask - InpStopLossPips * pip, _Digits);
   double tp = NormalizeDouble(tick.ask + InpTakeProfitPips * pip, _Digits);
   double lots = NormalizedLots();

   bool ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, "Jarvis RSI BUY");
   if(!ok)
      Print("BUY gagal. Retcode=", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   else
      Print("Permintaan BUY terkirim. Lots=", lots, " SL=", sl, " TP=", tp);
}

void OpenSell()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double pip = PipSize();
   double sl = NormalizeDouble(tick.bid + InpStopLossPips * pip, _Digits);
   double tp = NormalizeDouble(tick.bid - InpTakeProfitPips * pip, _Digits);
   double lots = NormalizedLots();

   bool ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, "Jarvis RSI SELL");
   if(!ok)
      Print("SELL gagal. Retcode=", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   else
      Print("Permintaan SELL terkirim. Lots=", lots, " SL=", sl, " TP=", tp);
}

int OnInit()
{
   if(InpRSIPeriod < 2 ||
      InpOverbought <= InpOversold ||
      InpOverbought > 100.0 ||
      InpOversold < 0.0 ||
      InpLots <= 0.0 ||
      InpStopLossPips <= 0.0 ||
      InpTakeProfitPips <= 0.0)
   {
      Print("Parameter EA tidak valid.");
      return INIT_PARAMETERS_INCORRECT;
   }

   rsiHandle = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Gagal membuat handle RSI. Error=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   double initialValue[1];
   if(CopyBuffer(rsiHandle, 0, 0, 1, initialValue) == 1)
      previousRsi = initialValue[0];

   Print("Jarvis RSI EA aktif pada ", _Symbol,
         ", RSI timeframe=", EnumToString(InpTimeframe),
         ", period=", InpRSIPeriod);
   Print("Menunggu persilangan RSI baru; tidak entry hanya karena RSI sudah ekstrem saat EA dipasang.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
}

void OnTick()
{
   if(rsiHandle == INVALID_HANDLE)
      return;

   double currentValue[1];
   if(CopyBuffer(rsiHandle, 0, 0, 1, currentValue) != 1)
      return;

   double currentRsi = currentValue[0];

   if(previousRsi == EMPTY_VALUE)
   {
      previousRsi = currentRsi;
      return;
   }

   bool sellSignal = (previousRsi < InpOverbought && currentRsi >= InpOverbought);
   bool buySignal = (previousRsi > InpOversold && currentRsi <= InpOversold);

   // Simpan nilai tick ini agar satu persilangan hanya memicu satu percobaan entry.
   previousRsi = currentRsi;

   if(HasOpenPositionOnSymbol())
      return;

   if(sellSignal)
      OpenSell();
   else if(buySignal)
      OpenBuy();
}
