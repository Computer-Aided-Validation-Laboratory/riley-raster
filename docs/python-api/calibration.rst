Calibration target motion
=========================

Generate rigid calibration-target displacement fields from explicit motion
limits, or constrain sampled poses to one camera's field of view. These
helpers and ``CalTargetMotionLimits`` are also available through top-level
``riley``. The range aliases are defined in ``riley.python.calibration``.

.. automodule:: riley.python.calibration
   :members: CalTargetMotionLimits, ECalTargetMotionSampling, MotionRange, AxisMotionRanges, caltarget_motion_from_limits, caltarget_motion_from_fov
