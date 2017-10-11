pragma SPARK_Mode;

with Types; use Types;

package Zumo_QTR is

   type Calibration is record
      Min : Sensor_Value := Sensor_Value'Last;
      Max : Sensor_Value := Sensor_Value'First;
   end record;

   type Calibration_Array is array (1 .. 6) of Calibration;

   Cal_Vals_On : Calibration_Array;
   Cal_Vals_Off : Calibration_Array;

   Initd : Boolean := False;

   procedure Init
     with Pre => not Initd,
     Post => Initd;

   procedure Read_Sensors (Sensor_Values : out Sensor_Array;
                           ReadMode      : Sensor_Read_Mode)
     with Pre => Initd;

   procedure ChangeEmitters (On : Boolean)
     with Global => null;

   procedure Calibrate (ReadMode : Sensor_Read_Mode := Emitters_On)
     with Pre => Initd;

   procedure ResetCalibration (ReadMode : Sensor_Read_Mode);

   procedure ReadCalibrated (Sensor_Values : out Sensor_Array;
                             ReadMode      : Sensor_Read_Mode)
     with Pre => Initd;

private

   procedure Read_Private (Sensor_Values : out Sensor_Array)
     with Pre => Initd;

   procedure Calibrate_Private (Cal_Vals : in out Calibration_Array;
                                ReadMode : Sensor_Read_Mode)
     with Pre => Initd;

end Zumo_QTR;
