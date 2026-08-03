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


//================== INPUTS ==================
input group "=== Colores ==="
input color   InpBuyColor      = C'41,98,255';    // Color Linea/Badge Compra
input color   InpSellColor     = clrCrimson;      // Color Linea/Badge Venta
input color   InpTPColor       = C'38,166,154';   // Color Linea/Badge Take Profit
input color   InpSLColor       = C'255,152,0';    // Color Linea/Badge Stop Loss
input color   InpBGColor       = clrWhite;        // Color Fondo Badges
input color   InpProfitFloat   = C'38,166,154';   // Color texto Profit
input color   InpLossFloat     = clrCrimson;      // Color texto Loss

input group "=== Badges ==="
input bool   InpPanelRight          = true;      // true = derecha : false = izquierda
input int    InpPanelMargin         = 6;         // Margen Pixeles borde izquierdo
input int    InpPriceScaleReserve   = 0;         // Margen Pixeles borde derecho
input int    InpButtonHeight        = 20;        // Alto de las cajas
input int    InpFontSize            = 8;         // Tamano de fuente
input string fontStyle              = "Segoe UI Semibold";   // Fuente del texto

// Enums para opciones de grosor
enum ENUM_LINE_WIDTH_OPTION
  {
   WIDTH_THIN   = 1, // Delgada (1 px)
   WIDTH_MEDIUM = 2, // Mediana (2 px)
   WIDTH_THICK  = 3  // Gruesa (3 px)
  };

input group "=== Grosor de Líneas ==="
input ENUM_LINE_WIDTH_OPTION InpLineWidth = WIDTH_MEDIUM; // Grosor de las líneas horizontales

bool    InpOnlyCurrentSymbol = true;
ulong   InpMagicFilter       = 0;      // 0 = mostrar todas


#define PFX "TM_"
#define TM_ZORDER 2147483647

double IndBuffer[];

//================== NOMBRES BASE ==================
string NamePosLine(ulong t)  { return PFX+"POSLN_"+(string)t; }
string NamePosRev(ulong t)   { return PFX+"POSRV_"+(string)t; }
string NamePosSLG(ulong t)   { return PFX+"POSSLG_"+(string)t; }
string NamePosTPG(ulong t)   { return PFX+"POSTPG_"+(string)t; }
string NamePosVol(ulong t)   { return PFX+"POSVOL_"+(string)t; }
string NamePosPnl(ulong t)   { return PFX+"POSPNL_"+(string)t; }
string NamePosClose(ulong t) { return PFX+"POSCL_"+(string)t; }

string NameSLLine(ulong t)   { return PFX+"SLLN_"+(string)t; }
string NameSLBadge(ulong t)  { return PFX+"SLBD_"+(string)t; }
string NameTPLine(ulong t)   { return PFX+"TPLN_"+(string)t; }
string NameTPBadge(ulong t)  { return PFX+"TPBD_"+(string)t; }

bool   InpShowReverseButton = false;
bool   InpShowCloseButton   = false;

//+------------------------------------------------------------------+
ulong TicketFromName(const string name)
  {
   int p = StringFind(name,"_");
   p = StringFind(name,"_",p+1);
   if(p<0) return 0;
   return (ulong)StringToInteger(StringSubstr(name,p+1));
  }
  

int PriceToY(double price)
  {
   double pmax = ChartGetDouble(0,CHART_PRICE_MAX,0);
   double pmin = ChartGetDouble(0,CHART_PRICE_MIN,0);
   int    h    = (int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(pmax<=pmin || h<=0) return 0;
   return (int)((pmax-price)/(pmax-pmin)*h);
  }

int ChartW(){ return (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0); }

int EffectiveMargin(){ return InpPanelRight ? InpPanelMargin+InpPriceScaleReserve : InpPanelMargin; }

int TextPixelWidth(const string t){ return (int)MathCeil(StringLen(t) * (InpFontSize * 0.70));}
int BoxWidthFor(const string t,int minW=75){ return MathMax(minW,TextPixelWidth(t)+16); }

void DeleteObj(const string name){ if(ObjectFind(0,name)>=0) ObjectDelete(0,name); }

//+------------------------------------------------------------------+
//| COMPONENTE: Linea horizontal estática                             |
//+------------------------------------------------------------------+
void DrawLine(const string name,double price,color clr,int width,ENUM_LINE_STYLE style,string tooltip)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,TM_ZORDER+5); // Se dibuja sobre los badges
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); // Bloqueada para no arrastrar
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
  }

//+------------------------------------------------------------------+
//| COMPONENTE: Caja plana (OBJ_RECTANGLE_LABEL)                      |
//+------------------------------------------------------------------+
void DrawBox(const string name, int screenX, int y, int w, int h, color bg, color border)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
     }
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, TM_ZORDER);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, screenX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
  }

//+------------------------------------------------------------------+
//| COMPONENTE: Texto (OBJ_LABEL) superpuesto                         |
//+------------------------------------------------------------------+
void DrawLabelIn(const string name, const string text, color fg, int boxScreenX, int boxY, int boxW, int boxH)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_FONT, fontStyle);
     }
   
   int pad = 5;
   int labelX = boxScreenX + pad;
   int labelY = boxY + MathMax(0, (boxH - (InpFontSize + 4)) / 2);

   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, TM_ZORDER+10);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, labelY);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, fontStyle);
  }

//+------------------------------------------------------------------+
//| COMPONENTE: Badge = Caja + Texto                                  |
//+------------------------------------------------------------------+
void DrawBadge(const string baseName, const string text, int screenX, int y, int w, int h,
               color bg, color fg, color border)
  {
   DrawBox(baseName + "B", screenX, y, w, h, bg, border);
   DrawLabelIn(baseName + "L", text, fg, screenX, y, w, h);
  }

void DeleteBadge(const string baseName){ DeleteObj(baseName+"B"); DeleteObj(baseName+"L"); }

//+------------------------------------------------------------------+
//| Fila de badges pegados unos a otros                               |
//+------------------------------------------------------------------+
void LayoutRow(string &names[], string &texts[], color &bgs[], color &fgs[], color &borders[],
                int &widths[], int n, int y, int h, int marginFromEdge)
  {
   if(n <= 0) return;

   int totalRowWidth = 0;
   for(int i = 0; i < n; i++) totalRowWidth += widths[i];

   int currentX = 0;
   if(InpPanelRight)
      currentX = ChartW() - marginFromEdge - totalRowWidth;
   else
      currentX = marginFromEdge;

   for(int i = 0; i < n; i++)
     {
      DrawBadge(names[i], texts[i], currentX, y, widths[i], h, bgs[i], fgs[i], borders[i]);
      currentX += widths[i];
     }
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
//| RECONSTRUCCION COMPLETA de una POSICION                           |
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
   double profit   = PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   color  lineClr  = isBuy ? InpBuyColor : InpSellColor;

   DrawLine(NamePosLine(ticket),priceOpen,lineClr,(int)InpLineWidth,STYLE_SOLID,(isBuy?"COMPRA ":"VENTA ")+DoubleToString(vol,2));
   int yLine = PriceToY(priceOpen);

   string names[6]; string texts[6]; color bgs[6]; color fgs[6]; color bords[6]; int ws[6];
   int n=0;

   if(!InpShowReverseButton) DeleteBadge(NamePosRev(ticket));
   if(sl>0) DeleteBadge(NamePosSLG(ticket));
   if(tp>0) DeleteBadge(NamePosTPG(ticket));

   // 1. Lotaje
   string volTxt = DoubleToString(vol,2);
   names[n]=NamePosVol(ticket); texts[n]=volTxt; bgs[n]=lineClr; fgs[n]=clrWhite; bords[n]=lineClr; ws[n]=BoxWidthFor(volTxt,32); n++;

   // 2. Beneficio con color condicional
   string pnlTxt = (profit>=0?"+":" ")+DoubleToString(profit,2)+" "+AccountInfoString(ACCOUNT_CURRENCY);
   color pnlTxtColor = (profit >= 0.0) ? InpProfitFloat : InpLossFloat;

   names[n]=NamePosPnl(ticket); texts[n]=pnlTxt; bgs[n]=InpBGColor; fgs[n]=pnlTxtColor; bords[n]=lineClr; ws[n]=BoxWidthFor(pnlTxt,60); n++;

   if(!InpShowCloseButton) DeleteBadge(NamePosClose(ticket));

   // Ubicamos la fila encima de la línea
   LayoutRow(names,texts,bgs,fgs,bords,ws,n,yLine - InpButtonHeight,InpButtonHeight,EffectiveMargin());

   // ---- SL activo ----
   if(sl>0)
     {
      DrawLine(NameSLLine(ticket),sl,InpSLColor,(int)InpLineWidth,STYLE_SOLID,"SL");
      string t=MoneyAtLevel(symbol,isBuy,vol,priceOpen,sl);
      int w = BoxWidthFor(t);
      int posX = InpPanelRight ? (ChartW() - EffectiveMargin() - w) : EffectiveMargin();
      DrawBadge(NameSLBadge(ticket),t,posX,PriceToY(sl) - InpButtonHeight,w,InpButtonHeight,
                InpBGColor,InpSLColor,InpSLColor);
     }

   // ---- TP activo ----
   if(tp>0)
     {
      DrawLine(NameTPLine(ticket),tp,InpTPColor,(int)InpLineWidth,STYLE_SOLID,"TP");
      string t=MoneyAtLevel(symbol,isBuy,vol,priceOpen,tp);
      int w = BoxWidthFor(t);
      int posX = InpPanelRight ? (ChartW() - EffectiveMargin() - w) : EffectiveMargin();
      DrawBadge(NameTPBadge(ticket),t,posX,PriceToY(tp) - InpButtonHeight,w,InpButtonHeight,
                InpBGColor,InpTPColor,InpTPColor);
     }
  }


//+------------------------------------------------------------------+
ulong g_livePos[];
bool InArray(ulong &arr[],ulong v){ for(int i=0;i<ArraySize(arr);i++) if(arr[i]==v) return true; return false; }

//+------------------------------------------------------------------+
void FullSync()
  {
   ArrayResize(g_livePos,0);

   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(InpOnlyCurrentSymbol && PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(InpMagicFilter!=0 && (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicFilter) continue;
      int n=ArraySize(g_livePos); ArrayResize(g_livePos,n+1); g_livePos[n]=ticket;
      SyncPosition(ticket);
     }

   int total = ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
     {
      string name = ObjectName(0,i,0,-1);
      if(StringFind(name,PFX)!=0) continue;
      ulong ticket = TicketFromName(name);
      if(!InArray(g_livePos,ticket)) ObjectDelete(0,name);
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void RefreshLive()
  {
   for(int i=0;i<ArraySize(g_livePos);i++) SyncPosition(g_livePos[i]);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int OnInit()
  { 
   FullSync(); 
   SetIndexBuffer(0, IndBuffer, INDICATOR_DATA);
   return(INIT_SUCCEEDED); 
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   int total = ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
     {
      string name = ObjectName(0,i,0,-1);
      if(StringFind(name,PFX)==0) ObjectDelete(0,name);
     }
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
   RefreshLive();
   FullSync(); 
   return(rates_total);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   FullSync();
  }
//+------------------------------------------------------------------+