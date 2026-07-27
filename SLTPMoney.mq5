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

//======================================================
// Configuración
//======================================================
input color SL_Color = C'239,83,80';      // Color SL
input color TP_Color = C'38,166,154';     // Color TP
input int     FontSize       = 8;
input string  FontName       = "Roboto";
input int     RefreshMS      = 100;
input int LabelXOffset = 18;   // Desplazamiento horizontal
input int LabelYOffset = -7;  // Desplazamiento vertical

//======================================================
// Prefijos
//======================================================

#define PREFIX "SLTPMONEY_"

//======================================================
// Prototipos
//======================================================

void UpdateLabels();
void DeleteLabels();

void DrawPosition(ulong ticket);

void CreateOrUpdateLabel(
   string name,
   string text,
   double price
);

double ProfitAtPrice(
   ENUM_POSITION_TYPE type,
   double volume,
   double openPrice,
   double closePrice
);

//======================================================
// Inicialización
//======================================================

int OnInit()
{
   UpdatePositions();
   Print("Indicador ejecutándose");
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Actualización por eventos de trading                             |
//+------------------------------------------------------------------+

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   UpdatePositions();
   Print("Actualizado");
   ChartRedraw();
}

void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam
)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      UpdatePositions();
      ChartRedraw();
   }
}

//======================================================
// Recorre todas las posiciones
//======================================================

void UpdateLabels()
{
   int total = PositionsTotal();

   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      DrawPosition(ticket);
   }
}

//======================================================
// Elimina todos los textos
//======================================================

void DeleteLabels()
{
   int total=ObjectsTotal(0);

   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i);

      if(StringFind(name,PREFIX)==0)
         ObjectDelete(0,name);
   }
}

//======================================================
// Calcula beneficio en un precio
//======================================================

double ProfitAtPrice(
   ENUM_POSITION_TYPE type,
   double volume,
   double openPrice,
   double closePrice
)
{
   double tickSize =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_SIZE
      );

   double tickValue =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_VALUE
      );


   if(tickSize<=0 || tickValue<=0)
      return(0);



   double priceDifference;


   if(type==POSITION_TYPE_BUY)
      priceDifference =
         closePrice - openPrice;
   else
      priceDifference =
         openPrice - closePrice;



   double ticks =
      priceDifference / tickSize;


   double profit =
      ticks * tickValue * volume;



   return(profit);
}

//======================================================
// Dibuja las etiquetas de una posición
//======================================================

string MoneyText(double money)
{
   if(money >= 0)
      return StringFormat("+$%.2f", money);

   return StringFormat("-$%.2f", MathAbs(money));
}

void DrawPosition(ulong ticket)
{
  
   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   double volume = PositionGetDouble(POSITION_VOLUME);
   double open   = PositionGetDouble(POSITION_PRICE_OPEN);

   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   
   
   
   if(sl>0)
   {
      double money = ProfitAtPrice(
         type,
         volume,
         open,
         sl);

      CreateOrUpdateLabel(
         PREFIX+"SL_"+(string)ticket,
         MoneyText(money),
         sl + (_Point * 5),
         SL_Color
      );
   }

   if(tp>0)
   {
      double money = ProfitAtPrice(
         type,
         volume,
         open,
         tp);

      CreateOrUpdateLabel(
         PREFIX+"TP_"+(string)ticket,
         MoneyText(money),
         tp - (_Point * 5),
         TP_Color
      );
   }
      
}

//+------------------------------------------------------------------+
//| Crea o actualiza una etiqueta                                   |
//+------------------------------------------------------------------+

void CreateOrUpdateLabel(
   string name,
   string text,
   double price,
   color labelColor
)
{
   int x;
   int y;


   // Convertir precio a coordenadas del gráfico

   datetime currentTime = TimeCurrent();


   if(!ChartTimePriceToXY(
         0,
         0,
         currentTime,
         price,
         x,
         y))
   {
      return;
   }



   // Crear etiqueta si no existe

   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(
         0,
         name,
         OBJ_LABEL,
         0,
         0,
         0
      );


      ObjectSetInteger(
         0,
         name,
         OBJPROP_COLOR,
         labelColor
      );


      ObjectSetInteger(
         0,
         name,
         OBJPROP_FONTSIZE,
         FontSize
      );


      ObjectSetString(
         0,
         name,
         OBJPROP_FONT,
         FontName
      );


      ObjectSetInteger(
         0,
         name,
         OBJPROP_ANCHOR,
         ANCHOR_LEFT
      );


      ObjectSetInteger(
         0,
         name,
         OBJPROP_SELECTABLE,
         false
      );


      ObjectSetInteger(
         0,
         name,
         OBJPROP_HIDDEN,
         true
      );
   }



   // Actualizar texto

   ObjectSetString(
      0,
      name,
      OBJPROP_TEXT,
      text
   );



   // Posición izquierda del gráfico

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      LabelXOffset
   );


   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y + LabelYOffset
   );
}
//+------------------------------------------------------------------+
//| Busca posiciones abiertas y actualiza etiquetas                  |
//+------------------------------------------------------------------+

void UpdatePositions()
{
   string active[];

   int total = PositionsTotal();

   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;


      ArrayResize(
         active,
         ArraySize(active)+1
      );

      active[ArraySize(active)-1] =
      PREFIX+"SL_"+(string)ticket;
      
      ArrayResize(
         active,
         ArraySize(active)+1
      );
      
      active[ArraySize(active)-1] =
      PREFIX+"TP_"+(string)ticket;

      DrawPosition(ticket);
   }


   RemoveOldLabels(active);
}



//+------------------------------------------------------------------+
//| Elimina etiquetas que ya no pertenecen a posiciones activas      |
//+------------------------------------------------------------------+

void RemoveOldLabels(string &active[])
{
   int total =
      ObjectsTotal(
         0,
         0,
         OBJ_TEXT
      );


   for(int i=total-1; i>=0; i--)
   {
      string name =
         ObjectName(
            0,
            i,
            0,
            OBJ_TEXT
         );


      if(StringFind(name,PREFIX)!=0)
         continue;


      bool exists=false;


      for(int j=0;j<ArraySize(active);j++)
      {
         if(StringFind(name,(string)active[j])>=0)
         {
            exists=true;
            break;
         }
      }


      if(!exists)
      {
         ObjectDelete(
            0,
            name
         );
      }
   }
}



int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
)
{
   return(rates_total);
}



//+------------------------------------------------------------------+
//| Limpieza al quitar indicador                                     |
//+------------------------------------------------------------------+

void OnDeinit(
   const int reason
)
{
   int total =
      ObjectsTotal(
         0
      );


   for(int i = total - 1; i >= 0; i--)
   {
      string name =
         ObjectName(
            0,
            i
         );


      if(StringFind(name, PREFIX) == 0)
      {
         ObjectDelete(
            0,
            name
         );
      }
   }


   ChartRedraw();
}