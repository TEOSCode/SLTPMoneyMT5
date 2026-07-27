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
input group "=== Colores (sistema propio, no depende del tema de MT5) ==="
input color   InpBuyColor      = C'41,98,255';    // Compra (linea, volumen, P/L, reversa)
input color   InpSellColor     = C'242,54,69';     // Venta
input color   InpTPColor       = C'38,166,154';     // Take Profit
input color   InpSLColor       = C'255,152,0';     // Stop Loss

input group "=== Panel ==="

input int     InpPanelMargin   = 6;      // Margen en pixeles desde el borde del grafico
input int     InpPriceScaleReserve = 78; // Pixeles reservados para no chocar con la escala de precio nativa de MT5 (sube este valor si tu escala se ve mas ancha, ej. simbolos con muchos digitos)
input int     InpButtonHeight  = 18;     // Alto de las cajas
input int     InpFontSize      = 8;      // Tamano de fuente

input group "=== Comportamiento ==="
input bool    InpOnlyCurrentSymbol = true;
input ulong   InpMagicFilter       = 0;      // 0 = mostrar todas
input int     InpTimerMs           = 200;    // Refresco ligero de P/L (ms)

#define PFX "TM_"
// Z-order maximo permitido por MT5 (int). Se aplica a TODOS nuestros objetos para
// que, dentro de la capa "foreground" (BACK=false), queden por encima de cualquier
// otro objeto/dibujo del grafico (lineas de tendencia, objetos de otros indicadores, etc.)
#define TM_ZORDER 2147483647

double IndBuffer[];

//================== NOMBRES BASE (cada uno = caja "B" + texto "L") ==================
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

string NamePendLine(ulong t)    { return PFX+"PDLN_"+(string)t; }
string NamePendSLG(ulong t)     { return PFX+"PDSLG_"+(string)t; }
string NamePendTPG(ulong t)     { return PFX+"PDTPG_"+(string)t; }
string NamePendVol(ulong t)     { return PFX+"PDVOL_"+(string)t; }
string NamePendDesc(ulong t)    { return PFX+"PDDESC_"+(string)t; }
string NamePendClose(ulong t)   { return PFX+"PDDL_"+(string)t; }
string NamePendSL(ulong t)      { return PFX+"PDSL_"+(string)t; }
string NamePendSLBadge(ulong t) { return PFX+"PDSLB_"+(string)t; }
string NamePendTP(ulong t)      { return PFX+"PDTP_"+(string)t; }
string NamePendTPBadge(ulong t) { return PFX+"PDTPB_"+(string)t; }

bool InpPanelRight = false;
double  InpPendingLightAmount = 0.35;        // Que tan clara se ve la linea de pendientes (0=color solido igual que la posicion, 1=casi blanca)
bool   InpShowReverseButton = false;
bool   InpShowCloseButton   = false;
color   InpCloseColor    = C'242,54,69';     // Texto del boton de cerrar/cancelar
color   InpBadgeBg       = clrWhite;         // Fondo de cajas informativas (TP/SL/desc)

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

ENUM_BASE_CORNER PanelCorner(){ return InpPanelRight ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER; }

// La escala de precio nativa de MT5 normalmente vive en el borde derecho. Si el panel
// esta a la derecha, sumamos una reserva para no dibujar debajo/encima de ella.
int EffectiveMargin(){ return InpPanelRight ? InpPanelMargin+InpPriceScaleReserve : InpPanelMargin; }

// Borde izquierdo en pantalla (independiente del corner) de una caja de ancho w situada
// a distancia x del borde correspondiente.
int BoxScreenLeft(int x,int w,ENUM_BASE_CORNER corner){ return (corner==CORNER_LEFT_UPPER)? x : ChartW()-x-w; }
// Conversion inversa: dado un borde izquierdo real en pantalla, la distancia x que hay
// que asignar en ese corner para que un objeto de ancho w quede ahi.
int ScreenLeftToX(int screenLeft,int w,ENUM_BASE_CORNER corner){ return (corner==CORNER_LEFT_UPPER)? screenLeft : ChartW()-screenLeft-w; }

int TextPixelWidth(const string t){ return (int)MathCeil(StringLen(t) * (InpFontSize * 0.75));}
int BoxWidthFor(const string t,int minW=20){ return MathMax(minW,TextPixelWidth(t)+24); }

color LightenColor(color c,double amount)
  {
   int r=(int)(c & 0xFF), g=(int)((c>>8)&0xFF), b=(int)((c>>16)&0xFF);
   r=(int)(r+(255-r)*amount); g=(int)(g+(255-g)*amount); b=(int)(b+(255-b)*amount);
   return (color)(r|(g<<8)|(b<<16));
  }

void DeleteObj(const string name){ if(ObjectFind(0,name)>=0) ObjectDelete(0,name); }

//+------------------------------------------------------------------+
//| COMPONENTE: Linea horizontal arrastrable                          |
//+------------------------------------------------------------------+
void DrawLine(const string name,double price,color clr,int width,ENUM_LINE_STYLE style,bool selectable,string tooltip)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,TM_ZORDER);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,selectable);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
  }

//+------------------------------------------------------------------+
//| COMPONENTE: Caja plana (OBJ_RECTANGLE_LABEL)                      |
//+------------------------------------------------------------------+
void DrawBox(const string name,int x,int y,int w,int h,color bg,color border,ENUM_BASE_CORNER corner)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
     }
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,TM_ZORDER);
   ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x-3);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y+8);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
  }

//+------------------------------------------------------------------+
//| COMPONENTE: Texto (OBJ_LABEL) superpuesto sobre una caja          |
//+------------------------------------------------------------------+
void DrawLabelIn(const string name,const string text,color fg,int boxX,int boxY,int boxW,int boxH,ENUM_BASE_CORNER corner)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
     }
   int pad = 6;
   int textW = TextPixelWidth(text);
   int screenLeftBox   = BoxScreenLeft(boxX,boxW,corner);
   int screenLeftLabel = screenLeftBox+pad;
   int labelX = ScreenLeftToX(screenLeftLabel,textW,corner);
   int labelY = boxY + MathMax(0,(boxH-(InpFontSize+6))/2);

   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,TM_ZORDER);
   ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,labelX-3);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,labelY+8);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,InpFontSize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,fg);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

//+------------------------------------------------------------------+
//| COMPONENTE: Badge = Caja + Texto (informativo o boton)            |
//+------------------------------------------------------------------+
void DrawBadge(const string baseName,const string text,int x,int y,int w,int h,
                color bg,color fg,color border,ENUM_BASE_CORNER corner)
  {
   DrawBox(baseName+"B",x,y,w,h,bg,border,corner);
   DrawLabelIn(baseName+"L",text,fg,x,y,w,h,corner);
  }

void DeleteBadge(const string baseName){ DeleteObj(baseName+"B"); DeleteObj(baseName+"L"); }

//+------------------------------------------------------------------+
//| Registro de zonas clicables (deteccion manual, sin OBJ_BUTTON)   |
//+------------------------------------------------------------------+
string g_clkName[]; int g_clkLeft[]; int g_clkTop[]; int g_clkRight[]; int g_clkBottom[];

void ClearClickRegistry()
  {
   ArrayResize(g_clkName,0); ArrayResize(g_clkLeft,0); ArrayResize(g_clkTop,0);
   ArrayResize(g_clkRight,0); ArrayResize(g_clkBottom,0);
  }

void RegisterClick(const string baseName,int x,int y,int w,int h,ENUM_BASE_CORNER corner)
  {
   int left = BoxScreenLeft(x,w,corner);
   int n = ArraySize(g_clkName);
   ArrayResize(g_clkName,n+1); ArrayResize(g_clkLeft,n+1); ArrayResize(g_clkTop,n+1);
   ArrayResize(g_clkRight,n+1); ArrayResize(g_clkBottom,n+1);
   g_clkName[n]=baseName; g_clkLeft[n]=left; g_clkTop[n]=y; g_clkRight[n]=left+w; g_clkBottom[n]=y+h;
  }

//+------------------------------------------------------------------+
//| Fila de badges pegados unos a otros, en orden de lectura          |
//| izquierda->derecha tal como se ve en pantalla                     |
//+------------------------------------------------------------------+
void LayoutRow(string &names[],string &texts[],color &bgs[],color &fgs[],color &borders[],
                int &widths[],bool &clickable[],int n,int y,int h,ENUM_BASE_CORNER corner,int marginFromEdge)
  {
   if(corner==CORNER_LEFT_UPPER || corner==CORNER_LEFT_LOWER)
     {
      int x = marginFromEdge;
      for(int i=0;i<n;i++)
        {
         DrawBadge(names[i],texts[i],x,y,widths[i],h,bgs[i],fgs[i],borders[i],corner);
         if(clickable[i]) RegisterClick(names[i],x,y,widths[i],h,corner);
         x += widths[i]+1;
        }
     }
   else
     {
      int x = marginFromEdge;
      for(int i=n-1;i>=0;i--)
        {
         DrawBadge(names[i],texts[i],x,y,widths[i],h,bgs[i],fgs[i],borders[i],corner);
         if(clickable[i]) RegisterClick(names[i],x,y,widths[i],h,corner);
         x += widths[i]+1;
        }
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
      // Forex, CFDs, acciones
      case SYMBOL_CALC_MODE_FOREX:
      case SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE:
      case SYMBOL_CALC_MODE_CFD:
      case SYMBOL_CALC_MODE_CFDINDEX:
      case SYMBOL_CALC_MODE_CFDLEVERAGE:
      case SYMBOL_CALC_MODE_EXCH_STOCKS:
      case SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX:
         profit = diff * contractSize * volume;
         break;

      // Futuros
      case SYMBOL_CALC_MODE_FUTURES:
      case SYMBOL_CALC_MODE_EXCH_FUTURES:
      case SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS:
         profit = (diff / tickSize) * tickValue * volume;
         break;

      // Bonos
      case SYMBOL_CALC_MODE_EXCH_BONDS:
      case SYMBOL_CALC_MODE_EXCH_BONDS_MOEX:
         profit = diff * contractSize * volume;
         break;

      // Modo desconocido: usar ticks
      default:
         profit = (diff / tickSize) * tickValue * volume;
         break;
   }

   string sign = (profit >= 0.0) ? "+" : "";

   return sign + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
}

//+------------------------------------------------------------------+
//| RECONSTRUCCION COMPLETA de una POSICION (estructura + badges)     |
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
   double point    = SymbolInfoDouble(symbol,SYMBOL_POINT); if(point<=0) point=_Point;

   DrawLine(NamePosLine(ticket),priceOpen,lineClr,2,STYLE_SOLID,false,(isBuy?"COMPRA ":"VENTA ")+DoubleToString(vol,2));
   int yLine = PriceToY(priceOpen);
   ENUM_BASE_CORNER corner = PanelCorner();

   string names[6]; string texts[6]; color bgs[6]; color fgs[6]; color bords[6]; int ws[6]; bool clk[6];
   int n=0;

   if(InpShowReverseButton)
     {
      /*names[n]=NamePosRev(ticket); texts[n]="R"; bgs[n]=lineClr; fgs[n]=clrWhite; bords[n]=lineClr; ws[n]=22; clk[n]=true; n++;*/
     }
   else DeleteBadge(NamePosRev(ticket));

   if(sl<=0){ /*names[n]=NamePosSLG(ticket); texts[n]="SL"; bgs[n]=InpBadgeBg; fgs[n]=InpSLColor; bords[n]=InpSLColor; ws[n]=20; clk[n]=false; n++; */}
   else DeleteBadge(NamePosSLG(ticket));

   if(tp<=0){ /*names[n]=NamePosTPG(ticket); texts[n]="TP"; bgs[n]=InpBadgeBg; fgs[n]=InpTPColor; bords[n]=InpTPColor; ws[n]=20; clk[n]=false; n++; */}
   else DeleteBadge(NamePosTPG(ticket));

   names[n]=NamePosVol(ticket); texts[n]=DoubleToString(vol,2); bgs[n]=lineClr; fgs[n]=clrWhite; bords[n]=lineClr; ws[n]=40; clk[n]=false; n++;

   names[n]=NamePosPnl(ticket); texts[n]=(profit>=0?"+":"")+DoubleToString(profit,2)+" "+AccountInfoString(ACCOUNT_CURRENCY);
   bgs[n]=lineClr; fgs[n]=clrWhite; bords[n]=lineClr; ws[n]=90; clk[n]=false; n++;

   if(InpShowCloseButton)
     {
      /*names[n]=NamePosClose(ticket); texts[n]="X"; bgs[n]=InpBadgeBg; fgs[n]=InpCloseColor; bords[n]=InpCloseColor; ws[n]=18; clk[n]=true; n++;*/
     }
   else DeleteBadge(NamePosClose(ticket));

   LayoutRow(names,texts,bgs,fgs,bords,ws,clk,n,yLine-InpButtonHeight/2,InpButtonHeight,corner,EffectiveMargin());

   // ---- SL activo: linea propia + badge con el DINERO en juego ----
   if(sl>0)
     {
     DrawLine(NameSLLine(ticket),sl,InpSLColor,2,STYLE_SOLID,true,"SL");
      string t="SL "+MoneyAtLevel(symbol,isBuy,vol,priceOpen,sl);
      DrawBadge(NameSLBadge(ticket),t,EffectiveMargin(),PriceToY(sl)-InpButtonHeight/2,BoxWidthFor(t,70),InpButtonHeight,
                InpSLColor,clrWhite,InpSLColor,corner);
     }
   

   // ---- TP activo: linea propia + badge con el DINERO en juego ----
   if(tp>0)
     {
      DrawLine(NameTPLine(ticket),tp,InpTPColor,2,STYLE_SOLID,true,"TP");
      string t="TP "+MoneyAtLevel(symbol,isBuy,vol,priceOpen,tp);
      DrawBadge(NameTPBadge(ticket),t,EffectiveMargin(),PriceToY(tp)-InpButtonHeight/2,BoxWidthFor(t,70),InpButtonHeight,
                InpTPColor,clrWhite,InpTPColor,corner);
     }
  
  }

//+------------------------------------------------------------------+
//| RECONSTRUCCION COMPLETA de una ORDEN PENDIENTE                    |
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
   color  sideClr= isBuy ? InpBuyColor : InpSellColor;
   color  lineClr= LightenColor(sideClr,InpPendingLightAmount); // mismo color de la posicion, solo mas claro
   double point  = SymbolInfoDouble(symbol,SYMBOL_POINT); if(point<=0) point=_Point;

   string typeTxt="Pendiente";
   if(type==ORDER_TYPE_BUY_LIMIT)  typeTxt="Comprar Limitada";
   if(type==ORDER_TYPE_SELL_LIMIT) typeTxt="Vender Limitada";
   if(type==ORDER_TYPE_BUY_STOP)   typeTxt="Comprar Stop";
   if(type==ORDER_TYPE_SELL_STOP)  typeTxt="Vender Stop";

   DrawLine(NamePendLine(ticket),price,lineClr,2,STYLE_DASHDOT,true,"Arrastra para mover la orden pendiente");
   int y = PriceToY(price);
   ENUM_BASE_CORNER corner = PanelCorner();

   string names[5]; string texts[5]; color bgs[5]; color fgs[5]; color bords[5]; int ws[5]; bool clk[5];
   int n=0;

   if(sl<=0){ names[n]=NamePendSLG(ticket); texts[n]="SL"; bgs[n]=InpBadgeBg; fgs[n]=InpSLColor; bords[n]=InpSLColor; ws[n]=50; clk[n]=false; n++; }
   else DeleteBadge(NamePendSLG(ticket));

   if(tp<=0){ names[n]=NamePendTPG(ticket); texts[n]="TP"; bgs[n]=InpBadgeBg; fgs[n]=InpTPColor; bords[n]=InpTPColor; ws[n]=50; clk[n]=false; n++; }
   else DeleteBadge(NamePendTPG(ticket));

   /*names[n]=NamePendVol(ticket); texts[n]=DoubleToString(vol,2); bgs[n]=sideClr; fgs[n]=clrWhite; bords[n]=sideClr; ws[n]=40; clk[n]=false; n++;
   names[n]=NamePendDesc(ticket); texts[n]=typeTxt; bgs[n]=sideClr; fgs[n]=clrWhite; bords[n]=sideClr; ws[n]=BoxWidthFor(typeTxt); clk[n]=false; n++;
   names[n]=NamePendClose(ticket); texts[n]="X"; bgs[n]=InpBadgeBg; fgs[n]=InpCloseColor; bords[n]=InpCloseColor; ws[n]=22; clk[n]=true; n++;*/

   LayoutRow(names,texts,bgs,fgs,bords,ws,clk,n,y-InpButtonHeight/2,InpButtonHeight,corner,EffectiveMargin());

   if(sl>0)
     {
      DrawLine(NamePendSL(ticket),sl,InpSLColor,1,STYLE_SOLID,true,"Arrastra para mover el SL de la pendiente");
      string t="SL "+MoneyAtLevel(symbol,isBuy,vol,price,sl);
      DrawBadge(NamePendSLBadge(ticket),t,EffectiveMargin(),PriceToY(sl)-InpButtonHeight/2,BoxWidthFor(t,70),InpButtonHeight,
                InpSLColor,clrWhite,InpSLColor,corner);
     }
 

   if(tp>0)
     {
      DrawLine(NamePendTP(ticket),tp,InpTPColor,1,STYLE_SOLID,true,"Arrastra para mover el TP de la pendiente");
      string t="TP "+MoneyAtLevel(symbol,isBuy,vol,price,tp);
      DrawBadge(NamePendTPBadge(ticket),t,EffectiveMargin(),PriceToY(tp)-InpButtonHeight/2,BoxWidthFor(t,70),InpButtonHeight,
                InpTPColor,clrWhite,InpTPColor,corner);
     }
 
  }

//+------------------------------------------------------------------+
//| Listas de tickets vivos (para limpiar huerfanos)                  |
//+------------------------------------------------------------------+
ulong g_livePos[]; ulong g_liveOrd[];
bool InArray(ulong &arr[],ulong v){ for(int i=0;i<ArraySize(arr);i++) if(arr[i]==v) return true; return false; }

//+------------------------------------------------------------------+
//| RECONSTRUCCION COMPLETA (estructura) - llamada desde              |
//| OnInit / OnTradeTransaction / tras drag / tras click / chart change|
//+------------------------------------------------------------------+
void FullSync()
  {
   ClearClickRegistry();
   ArrayResize(g_livePos,0); ArrayResize(g_liveOrd,0);

   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(InpOnlyCurrentSymbol && PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(InpMagicFilter!=0 && (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicFilter) continue;
      int n=ArraySize(g_livePos); ArrayResize(g_livePos,n+1); g_livePos[n]=ticket;
      SyncPosition(ticket);
     }

   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(InpOnlyCurrentSymbol && OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if(InpMagicFilter!=0 && (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicFilter) continue;
      int n=ArraySize(g_liveOrd); ArrayResize(g_liveOrd,n+1); g_liveOrd[n]=ticket;
      SyncPending(ticket);
     }

   int total = ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
     {
      string name = ObjectName(0,i,0,-1);
      if(StringFind(name,PFX)!=0) continue;
      ulong ticket = TicketFromName(name);
      bool isPend = (StringFind(name,PFX+"PD")==0);
      if(isPend) { if(!InArray(g_liveOrd,ticket)) ObjectDelete(0,name); }
      else       { if(!InArray(g_livePos,ticket)) ObjectDelete(0,name); }
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| ACTUALIZACION LIGERA - OnTick/OnTimer                             |
//| Reposiciona (por el autoescalado de precio) y refresca el texto  |
//| de las posiciones/ordenes YA CONOCIDAS (arrays g_livePos/g_liveOrd)|
//| Es barato: solo toca los objetos de las operaciones abiertas,    |
//| NO escanea todos los objetos del grafico (eso lo hace FullSync). |
//+------------------------------------------------------------------+
void RefreshLive()
  {
   ClearClickRegistry();
   for(int i=0;i<ArraySize(g_livePos);i++) SyncPosition(g_livePos[i]);
   for(int i=0;i<ArraySize(g_liveOrd);i++) SyncPending(g_liveOrd[i]);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int OnInit(){ EventSetMillisecondTimer(InpTimerMs); FullSync(); return(INIT_SUCCEEDED); SetIndexBuffer(0, IndBuffer, INDICATOR_DATA); }

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

// OnTick/OnTimer: reposiciona y refresca SOLO las operaciones ya conocidas
// (barato, sin escanear todos los objetos del grafico). La reconstruccion
// estructural completa (altas/bajas/orphans) sigue viviendo en FullSync().


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
   RefreshLive(); 
   return(rates_total);
  }
// OnTradeTransaction: aqui vive la reconstruccion estructural (posiciones/ordenes
// que aparecen, desaparecen o cambian SL/TP/precio).
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   FullSync();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_DRAG)
     {
      string name = sparam;
      if(StringFind(name,PFX)!=0) return;
      double newPrice = ObjectGetDouble(0,name,OBJPROP_PRICE);

      /*if(StringFind(name,PFX+"SLLN_")==0 || StringFind(name,PFX+"TPLN_")==0)
         HandleDragPositionLevel(name,newPrice);
      else if(StringFind(name,PFX+"PDLN_")==0 || StringFind(name,PFX+"PDSL_")==0 || StringFind(name,PFX+"PDTP_")==0)
         HandleDragPendingLevel(name,newPrice);*/

      FullSync();
     }
   else if(id==CHARTEVENT_CLICK)
     {
      int px=(int)lparam, py=(int)dparam;
      for(int i=0;i<ArraySize(g_clkName);i++)
        {
         if(px>=g_clkLeft[i] && px<=g_clkRight[i] && py>=g_clkTop[i] && py<=g_clkBottom[i])
           {
            /*DispatchClick(g_clkName[i]);*/
            FullSync();
            break;
           }
        }
     }
   else if(id==CHARTEVENT_CHART_CHANGE)
     {
      // Cambio de escala/zoom/scroll: hay que reposicionar (no es un tick, es poco frecuente)
      FullSync();
     }
  }
//+------------------------------------------------------------------+