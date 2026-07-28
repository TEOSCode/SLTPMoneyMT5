//+------------------------------------------------------------------+
//|                                                    SLTPMoney.mq5 |
//|                                        Copyright 2026, LemuzLabs |
//|                                  https://lemuzlabs.blogspot.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LemuzLabs"
#property link      "https://lemuzlabs.blogspot.com/"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

#include <Canvas\Canvas.mqh>

//--- Opciones de alineación horizontal para los badges
enum ENUM_BADGE_ALIGNMENT
{
   BADGE_ALIGN_LEFT,    // Alineados a la izquierda
   BADGE_ALIGN_CENTER,  // Alineados al centro del gráfico
   BADGE_ALIGN_RIGHT    // Alineados a la derecha (cerca del precio)
};

//--- Opciones de grosor para las líneas horizontales
enum ENUM_LINE_THICKNESS
{
   THICK_1 = 1, // 1 píxel (Fina)
   THICK_2 = 2, // 2 píxeles (Media)
   THICK_3 = 3  // 3 píxeles (Gruesa)
};

//================== INPUTS ==================
input group "=== Colores (sistema propio, no depende del tema de MT5) ==="
input color   InpBuyColor      = C'41,98,255';    // Compra (linea, volumen, P/L, reversa)
input color   InpSellColor     = clrCrimson;     // Venta
input color   InpTPColor       = C'38,166,154';     // Take Profit
input color   InpSLColor       = C'255,152,0';     // Stop Loss
input color   InpProfitFloat   = C'38,166,154';          // Color texto Profit
input color   InpLossFloat     = C'255,152,0';   // Color texto Loss

input group "=== Apariencia UI Canvas ==="
input ENUM_BADGE_ALIGNMENT InpAlignment = BADGE_ALIGN_RIGHT; // Alineación horizontal de badges
input ENUM_LINE_THICKNESS  InpLineThick = THICK_2;            // Grosor línea horizontal (1, 2 ó 3 px)
input color   InpBadgeInnerBg  = clrWhite;   // Fondo interior claro para contraste
input int     InpFontSize      = 15;               // Tamaño de fuente (Arial) para todo el texto
input bool    showRightTriangle = true;

input group "=== Comportamiento ==="
input bool    InpOnlyCurrentSymbol = true;
input ulong   InpMagicFilter       = 0;      // 0 = mostrar todas
input int     InpTimerMs           = 200;    // Refresco ligero de P/L (ms)

#define PFX "TM_"
#define COLOR_TEXT_WHITE 0xFFFFFFFF

double IndBuffer[];
CCanvas canvas;

//+------------------------------------------------------------------+
//| Convertidor de color MQL5 a ARGB opaco                           |
//+------------------------------------------------------------------+
uint ToARGB(color clr, uchar alpha=255)
{
   return ((uint)alpha << 24) | ((uint)(clr & 0xFF) << 16) | ((uint)((clr >> 8) & 0xFF) << 8) | (uint)((clr >> 16) & 0xFF);
}

//+------------------------------------------------------------------+
//| Función auxiliar para dibujar rectángulos con bordes redondeados  |
//+------------------------------------------------------------------+
void DrawRoundedRect(int x1, int y1, int x2, int y2, int r, uint clr)
{
   if(r <= 0)
   {
      canvas.FillRectangle(x1, y1, x2, y2, clr);
      return;
   }

   int width = MathAbs(x2 - x1);
   int height = MathAbs(y2 - y1);
   r = MathMin(r, MathMin(width / 2, height / 2));

   canvas.FillRectangle(x1 + r, y1, x2 - r, y2, clr);
   canvas.FillRectangle(x1, y1 + r, x2, y2 - r, clr);

   canvas.FillCircle(x1 + r, y1 + r, r, clr);
   canvas.FillCircle(x2 - r, y1 + r, r, clr);
   canvas.FillCircle(x1 + r, y2 - r, r, clr);
   canvas.FillCircle(x2 - r, y2 - r, r, clr);
}

//+------------------------------------------------------------------+
//| Dinero (no precio) que representa un nivel de SL o TP             |
//+------------------------------------------------------------------+
string MoneyAtLevel(string symbol, bool isBuy, double volume, double priceRef, double level)
{
   double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   ENUM_SYMBOL_CALC_MODE calcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);

   if(contractSize <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
      return "--";

   double profit = 0.0;
   double diff = isBuy ? (level - priceRef) : (priceRef - level);

   switch(calcMode)
   {
      case SYMBOL_CALC_MODE_FOREX:
      case SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE:
      case SYMBOL_CALC_MODE_CFD:
      case SYMBOL_CALC_MODE_CFDINDEX:
      case SYMBOL_CALC_MODE_CFDLEVERAGE:
      case SYMBOL_CALC_MODE_EXCH_STOCKS:
      case SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX:
         profit = diff * contractSize * volume;
         break;

      case SYMBOL_CALC_MODE_FUTURES:
      case SYMBOL_CALC_MODE_EXCH_FUTURES:
      case SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS:
         profit = (diff / tickSize) * tickValue * volume;
         break;

      case SYMBOL_CALC_MODE_EXCH_BONDS:
      case SYMBOL_CALC_MODE_EXCH_BONDS_MOEX:
         profit = diff * contractSize * volume;
         break;

      default:
         profit = (diff / tickSize) * tickValue * volume;
         break;
   }

   string sign = (profit >= 0.0) ? "+" : "";
   return sign + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
}

//+------------------------------------------------------------------+
//| Función de Renderizado Visual del Badge con CCanvas              |
//+------------------------------------------------------------------+
void DrawPositionBadge(double price, string labelText, uint clrOutline, uint clrInnerBg, uint clrText, ENUM_BADGE_ALIGNMENT alignMode, string leftBoxText = "")
{
   int xDummy, y;

   if(!ChartTimePriceToXY(0, 0, TimeCurrent(), price, xDummy, y))
      return;

   int chartWidth = canvas.Width();

   canvas.FontSet("Arial", InpFontSize, FW_BOLD);

   int badgeW      = MathMax(10, (InpFontSize * 7)); 
   int badgeH      = MathMax(3, InpFontSize + 4);  
   int arrowW      = 10;   
   int borderThick = 1;   
   int cornerRadius= 1; // Radio para esquinas redondeadas

   int bx = 0;
   switch(alignMode)
   {
      case BADGE_ALIGN_LEFT:   bx = 75; break;
      case BADGE_ALIGN_CENTER: bx = (chartWidth / 2) - (badgeW / 2); break;
      case BADGE_ALIGN_RIGHT:  bx = chartWidth - badgeW - arrowW - 5; break;
   }

   // Badge posicionado por encima de la línea del precio
   int by = y - badgeH;

   // --- Recuadro a la Izquierda (Lotaje/Volumen) ---
   if(StringLen(leftBoxText) > 0)
   {
      int boxW = MathMax(28, (InpFontSize * 3));

      DrawRoundedRect(bx - boxW, by, bx - 1, by + badgeH, cornerRadius, clrOutline);

      int w, h;
      canvas.TextSize(leftBoxText, w, h);
      canvas.TextOut(bx - boxW + (boxW - w) / 2, by + (badgeH - h) / 2, leftBoxText, COLOR_TEXT_WHITE);
   }

   // 1. Marco Exterior Redondeado (Outline)
   DrawRoundedRect(bx, by, bx + badgeW, by + badgeH, cornerRadius, clrOutline);

   // 2. Flecha a la derecha
   if(showRightTriangle){
      int px[3];
      int py[3];
   
      px[0] = bx + badgeW;          py[0] = by + 2;
      px[1] = bx + badgeW + arrowW; py[1] = y;
      px[2] = bx + badgeW;          py[2] = by + badgeH;
   
      canvas.FillTriangle(px[0], py[0], px[1], py[1], px[2], py[2], clrOutline);
   }
  
   // 3. Línea horizontal constante hacia el borde derecho con grosor configurable (1, 2 ó 3)
   // Dibuja un bloque horizontal sólido, eliminando el halo negro del anti-aliasing
   int thick = (int)InpLineThick;
   int yStart = y - (thick / 2);
   
   for(int i = 0; i < thick; i++)
   {
      canvas.LineHorizontal(0, chartWidth, yStart + i, clrOutline);
   }

   // 4. Recuadro Interior Redondeado
   int innerX1 = bx + borderThick;
   int innerY1 = by + borderThick;
   int innerX2 = bx + badgeW - borderThick;
   int innerY2 = by + badgeH - borderThick;

   int innerRadius = MathMax(1, cornerRadius - borderThick);
   DrawRoundedRect(innerX1, innerY1, innerX2, innerY2, innerRadius, clrInnerBg);

   // 5. Texto principal centrado
   int textWidth, textHeight;
   canvas.TextSize(labelText, textWidth, textHeight);

   int textX = innerX1 + ((innerX2 - innerX1) - textWidth) / 2;
   int textY = innerY1 + ((innerY2 - innerY1) - textHeight) / 2;

   canvas.TextOut(textX, textY, labelText, clrText);
}

//+------------------------------------------------------------------+
//| RECONSTRUCCION Y DIBUJADO DE POSICIONES ACTIVAS                  |
//+------------------------------------------------------------------+
void SyncPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   string symbol   = PositionGetString(POSITION_SYMBOL);
   bool   isBuy    = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double priceOpen= PositionGetDouble(POSITION_PRICE_OPEN);
   double sl       = PositionGetDouble(POSITION_SL);
   double tp       = PositionGetDouble(POSITION_TP);
   double vol      = PositionGetDouble(POSITION_VOLUME);
   double profit   = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   
   uint outlineClr = isBuy ? ToARGB(InpBuyColor) : ToARGB(InpSellColor);
   uint innerBgClr = ToARGB(InpBadgeInnerBg);
   uint textClr    = (profit >= 0.0) ? ToARGB(InpProfitFloat) : ToARGB(InpLossFloat);

   string volTxt = DoubleToString(vol, 2);
   string pnlTxt = (profit >= 0.0 ? "+" : "") + DoubleToString(profit, 2);

   DrawPositionBadge(priceOpen, pnlTxt, outlineClr, innerBgClr, textClr, InpAlignment, volTxt);

   if(sl > 0)
   {
      uint slOutlineClr = ToARGB(InpSLColor);
      string slTxt = MoneyAtLevel(symbol, isBuy, vol, priceOpen, sl);
      DrawPositionBadge(sl, slTxt, slOutlineClr, innerBgClr, slOutlineClr, InpAlignment);
   }

   if(tp > 0)
   {
      uint tpOutlineClr = ToARGB(InpTPColor);
      string tpTxt = MoneyAtLevel(symbol, isBuy, vol, priceOpen, tp);
      DrawPositionBadge(tp, tpTxt, tpOutlineClr, innerBgClr, tpOutlineClr, InpAlignment);
   }
}

//+------------------------------------------------------------------+
//| RECONSTRUCCION Y DIBUJADO DE ORDENES PENDIENTES                  |
//+------------------------------------------------------------------+
void SyncPending(ulong ticket)
{
   if(!OrderSelect(ticket)) return;
   string symbol = OrderGetString(ORDER_SYMBOL);
   long   type   = OrderGetInteger(ORDER_TYPE);
   double price  = OrderGetDouble(ORDER_PRICE_OPEN);
   double sl     = OrderGetDouble(ORDER_SL);
   double tp     = OrderGetDouble(ORDER_TP);
   double vol    = OrderGetDouble(ORDER_VOLUME_CURRENT);
   bool   isBuy  = (type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
   
   uint outlineClr = isBuy ? ToARGB(InpBuyColor) : ToARGB(InpSellColor);
   uint innerBgClr = ToARGB(InpBadgeInnerBg);

   string volTxt = DoubleToString(vol, 2);

   DrawPositionBadge(price, "PEND", outlineClr, innerBgClr, outlineClr, InpAlignment, volTxt);

   if(sl > 0)
   {
      uint slOutlineClr = ToARGB(InpSLColor);
      string slTxt = MoneyAtLevel(symbol, isBuy, vol, price, sl);
      DrawPositionBadge(sl, slTxt, slOutlineClr, innerBgClr, slOutlineClr, InpAlignment);
   }

   if(tp > 0)
   {
      uint tpOutlineClr = ToARGB(InpTPColor);
      string tpTxt = MoneyAtLevel(symbol, isBuy, vol, price, tp);
      DrawPositionBadge(tp, tpTxt, tpOutlineClr, innerBgClr, tpOutlineClr, InpAlignment);
   }
}

//+------------------------------------------------------------------+
//| Sincronización general y renderizado en Canvas                    |
//+------------------------------------------------------------------+
void FullSync()
{
   int width  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   if(width <= 0 || height <= 0) return;

   if(canvas.Width() != width || canvas.Height() != height)
      canvas.Resize(width, height);

   canvas.Erase(0x00000000);

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(InpOnlyCurrentSymbol && PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(InpMagicFilter != 0 && (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicFilter) continue;
      
      SyncPosition(ticket);
   }

   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(InpOnlyCurrentSymbol && OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(InpMagicFilter != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicFilter) continue;
      
      SyncPending(ticket);
   }

   canvas.Update();
}

//+------------------------------------------------------------------+
//| EVENTOS DEL INDICADOR                                            |
//+------------------------------------------------------------------+
int OnInit()
{ 
   int width  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   if(width <= 0 || height <= 0)
   {
      width  = 800;
      height = 600;
   }

   if(!canvas.CreateBitmapLabel(0, 0, "SLTPMoneyCanvas", 0, 0, width, height, COLOR_FORMAT_ARGB_NORMALIZE))
   {
      Print("Error al crear el Canvas para SLTPMoney");
      return(INIT_FAILED);
   }

   string objName = canvas.ChartObjectName();
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_ZORDER, 2147483647);

   EventSetMillisecondTimer(InpTimerMs); 
   SetIndexBuffer(0, IndBuffer, INDICATOR_DATA);
   FullSync(); 
   return(INIT_SUCCEEDED); 
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   canvas.Destroy();
   ChartRedraw(0);
}

int OnCalculate(const int32_t rates_total,
                const int32_t prev_calculated,
                const datetime& time[],
                const double& open[],
                const double& high[],
                const double& low[],
                const double& close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[])
{
   FullSync();
   return(rates_total);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   FullSync();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      FullSync();
   }
}
//+------------------------------------------------------------------+