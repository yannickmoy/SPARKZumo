pragma SPARK_Mode;

with Interfaces.C; use Interfaces.C;

package body Line_Finder is

   Noise_Threshold : constant := Timeout / 10;
   Line_Threshold  : constant := Timeout / 2;

   Fast_Speed      : constant := Motor_Speed'Last - 150;
   Slow_Speed      : constant := Fast_Speed;

   procedure LineFinder (ReadMode : Sensor_Read_Mode)
   is
      Line_State : LineState;
      State_Thresh : Boolean;
   begin
      ReadLine (WhiteLine  => True,
                ReadMode   => ReadMode,
                State => Line_State);

      case BotState.Decision is
         when Simple =>
            SimpleDecisionMatrix (State => Line_State);
         when Complex =>
            Geo_Filter.FilterState (State => Line_State,
                                    Thresh => State_Thresh);

            DecisionMatrix (State        => Line_State,
                            State_Thresh => State_Thresh);
      end case;
   end LineFinder;

   procedure ReadLine (WhiteLine      : Boolean;
                      ReadMode       : Sensor_Read_Mode;
                      State      : out LineState)
   is
   begin
      Zumo_QTR.ReadCalibrated (Sensor_Values => BotState.Sensor_Values,
                               ReadMode      => ReadMode);

      BotState.LineDetect := 0;

      for I in BotState.Sensor_Values'Range loop
         if WhiteLine then
            BotState.Sensor_Values (I) :=
              Sensor_Value'Last - BotState.Sensor_Values (I);
         end if;

         --  keep track of whether we see the line at all
         if BotState.Sensor_Values (I) > Line_Threshold then
            BotState.LineDetect := BotState.LineDetect +
              2 ** (I - BotState.Sensor_Values'First);
         end if;
      end loop;

      State := LineStateLookup (Integer (BotState.LineDetect));

   end ReadLine;

   function CalculateBotPosition return Robot_Position
   is
      Ret : Robot_Position;

      Avg     : long := 0;
      Sum     : long := 0;
   begin
      for I in BotState.Sensor_Values'Range loop
         if BotState.Sensor_Values (I) >  Noise_Threshold then
            Avg := Avg + long (BotState.Sensor_Values (I)) * (long (I - 1) *
                                           long (Sensor_Value'Last));
            Sum := Sum + long (BotState.Sensor_Values (I));
         end if;

      end loop;

      if Sum /= 0 then
         BotState.SensorValueHistory := Integer (Avg / Sum);

         if BotState.SensorValueHistory > Robot_Position'Last * 2 then
            BotState.SensorValueHistory := Robot_Position'Last * 2;
         end if;

         Ret := Natural (BotState.SensorValueHistory) -
           Robot_Position'Last;

         if Ret < 0 then
            BotState.OrientationHistory := Left;
         elsif Ret > 0 then
            BotState.OrientationHistory := Right;
         else
            BotState.OrientationHistory := Center;
         end if;
      else
         Ret := Robot_Position'First;
      end if;

      return Ret;

   end CalculateBotPosition;

   procedure SimpleDecisionMatrix (State : LineState)
   is
      LeftSpeed : Motor_Speed;
      RightSpeed : Motor_Speed;

      LS_Saturate : Integer;
      RS_Saturate : Integer;
   begin
      case State is
         when Lost =>
            case BotState.OrientationHistory is
               when Left | Center =>
                  LS_Saturate := (-1) * Fast_Speed + BotState.OfflineCounter;
                  RightSpeed := Fast_Speed;

                  if LS_Saturate > Motor_Speed'Last then
                     LeftSpeed := Motor_Speed'Last;
                  elsif LS_Saturate < Motor_Speed'First then
                     LeftSpeed := Motor_Speed'First;
                  else
                     LeftSpeed := LS_Saturate;
                  end if;
               when Right =>
                  LeftSpeed := Fast_Speed;
                  RS_Saturate := (-1) * Fast_Speed + BotState.OfflineCounter;

                  if RS_Saturate > Motor_Speed'Last then
                     RightSpeed := Motor_Speed'Last;
                  elsif RS_Saturate < Motor_Speed'First then
                     RightSpeed := Motor_Speed'First;
                  else
                     RightSpeed := RS_Saturate;
                  end if;
            end case;

            if BotState.OfflineCounter = OfflineCounterType'Last then
               BotState.OfflineCounter := OfflineCounterType'First;
            else
               BotState.OfflineCounter := BotState.OfflineCounter + 1;
            end if;

            Zumo_LED.Yellow_Led (On => False);
         when others =>
            BotState.LostCounter := 0;
            BotState.Decision := Complex;

            BotState.OfflineCounter := 0;
            Zumo_LED.Yellow_Led (On => True);

            Error_Correct (Error         => CalculateBotPosition,
                           Current_Speed => Fast_Speed,
                           LeftSpeed     => LeftSpeed,
                           RightSpeed    => RightSpeed);
      end case;

      Zumo_Motors.SetSpeed (LeftVelocity  => LeftSpeed,
                            RightVelocity => RightSpeed);

--      Serial_Print (Msg => LineStateStr (State));

      BotState.LineHistory := State;
   end SimpleDecisionMatrix;

   procedure DecisionMatrix (State        : LineState;
                             State_Thresh : Boolean)
   is
      LeftSpeed : Motor_Speed;
      RightSpeed : Motor_Speed;

      Mod_State : LineState;
   begin
      if State_Thresh then
         Mod_State := State;
      else
         Mod_State := Unknown;
      end if;

      case Mod_State is
         when BranchLeft =>
            BotState.LostCounter := 0;
            Zumo_LED.Yellow_Led (On => False);

            Zumo_Motors.SetSpeed (LeftVelocity  => 0,
                                  RightVelocity => Slow_Speed);
         when BranchRight =>
            BotState.LostCounter := 0;
            Zumo_LED.Yellow_Led (On => False);

            Zumo_Motors.SetSpeed (LeftVelocity  => Slow_Speed,
                                  RightVelocity => 0);
         when Perp | Fork =>
            BotState.LostCounter := 0;
            case BotState.OrientationHistory is
               when Left | Center =>
                  LeftSpeed := 0;
                  RightSpeed := Slow_Speed;
               when Right =>
                  LeftSpeed := Slow_Speed;
                  RightSpeed := 0;
            end case;

            Zumo_LED.Yellow_Led (On => False);

            Zumo_Motors.SetSpeed (LeftVelocity  => LeftSpeed,
                                  RightVelocity => RightSpeed);
         when Lost =>
            case BotState.OrientationHistory is
               when Left | Center =>
                  LeftSpeed := (-1) * Fast_Speed;
                  RightSpeed := Fast_Speed;
               when Right =>
                  LeftSpeed := Fast_Speed;
                  RightSpeed := (-1) * Fast_Speed;
            end case;

            Zumo_LED.Yellow_Led (On => False);

            Zumo_Motors.SetSpeed (LeftVelocity  => LeftSpeed,
                                  RightVelocity => RightSpeed);

            if BotState.LostCounter > Lost_Threshold then
               BotState.Decision := Simple;
            else
               BotState.LostCounter := BotState.LostCounter + 1;
            end if;
         when Online =>
            BotState.LostCounter := 0;
            Zumo_LED.Yellow_Led (On => True);

            Error_Correct (Error         => CalculateBotPosition,
                           Current_Speed => Fast_Speed,
                           LeftSpeed     => LeftSpeed,
                           RightSpeed    => RightSpeed);

            Zumo_Motors.SetSpeed (LeftVelocity  => LeftSpeed,
                                  RightVelocity => RightSpeed);
         when Unknown =>
            null;
      end case;

      BotState.LineHistory := Mod_State;
   end DecisionMatrix;

   procedure Error_Correct (Error         : Robot_Position;
                            Current_Speed : Motor_Speed;
                            LeftSpeed     : out Motor_Speed;
                            RightSpeed    : out Motor_Speed)
   is
      Inv_Prop              : constant := 8;
      Deriv                 : constant := 2;

      SpeedDifference : Integer;

      Saturate_Speed : Integer;
   begin

      SpeedDifference := Error / Inv_Prop + Deriv *
        (Error - BotState.ErrorHistory);

      BotState.ErrorHistory := Error;

      if SpeedDifference > Motor_Speed'Last then
         SpeedDifference := Current_Speed;
      elsif SpeedDifference < Motor_Speed'First then
         SpeedDifference := Current_Speed;
      end if;

      if SpeedDifference < 0 then
         Saturate_Speed := Current_Speed + Motor_Speed (SpeedDifference);
         if Saturate_Speed > Motor_Speed'Last then
            LeftSpeed := Motor_Speed'Last;
         elsif Saturate_Speed < Motor_Speed'First then
            LeftSpeed := Motor_Speed'First;
         else
            LeftSpeed := Saturate_Speed;
         end if;
         RightSpeed := Current_Speed;
      else
         LeftSpeed := Current_Speed;

         Saturate_Speed := Current_Speed - Motor_Speed (SpeedDifference);
         if Saturate_Speed > Motor_Speed'Last then
            RightSpeed := Motor_Speed'Last;
         elsif Saturate_Speed < Motor_Speed'First then
            RightSpeed := Motor_Speed'First;
         else
            RightSpeed := Saturate_Speed;
         end if;
      end if;

   end Error_Correct;

end Line_Finder;
