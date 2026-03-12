using Expansions.Missions;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

namespace AFS
{
    internal class FlightControlUtils
    {
        /// <summary>
        /// This is a replacement for the stock API Property "vessel.MOI", which seems buggy when used
        /// with "control from here" on parts other than the default control part.
        /// <br/>
        /// Right now the stock Moment of Inertia Property returns values in inconsistent reference frames that
        /// don't make sense when used with "control from here".  (It doesn't merely rotate the reference frame, as one
        /// would expect "control from here" to do.)
        /// </summary>   
        /// TODO: Check this again after each KSP stock release to see if it's been changed or not.
        public static Vector3 FindMoI(Vessel vessel)
        {
            var tensor = Matrix4x4.zero;
            Matrix4x4 partTensor = Matrix4x4.identity;
            Matrix4x4 inertiaMatrix = Matrix4x4.identity;
            Matrix4x4 productMatrix = Matrix4x4.identity;
            Transform vesselTransform = vessel.ReferenceTransform;
            Quaternion vesselRotation = vesselTransform.rotation * Quaternion.Euler(-90, 0, 0);
            Vector3d centerOfMass = vessel.CoMD;
            foreach (var part in vessel.Parts)
            {
                if (part.rb != null)
                {
                    KSPUtil.ToDiagonalMatrix2(part.rb.inertiaTensor, ref partTensor);

                    Quaternion rot = Quaternion.Inverse(vesselRotation) * part.transform.rotation * part.rb.inertiaTensorRotation;
                    Quaternion inv = Quaternion.Inverse(rot);

                    Matrix4x4 rotMatrix = Matrix4x4.TRS(Vector3.zero, rot, Vector3.one);
                    Matrix4x4 invMatrix = Matrix4x4.TRS(Vector3.zero, inv, Vector3.one);

                    // add the part inertiaTensor to the ship inertiaTensor
                    KSPUtil.Add(ref tensor, rotMatrix * partTensor * invMatrix);

                    Vector3 position = vesselTransform.InverseTransformDirection(part.rb.position - centerOfMass);

                    // add the part mass to the ship inertiaTensor
                    KSPUtil.ToDiagonalMatrix2(part.rb.mass * position.sqrMagnitude, ref inertiaMatrix);
                    KSPUtil.Add(ref tensor, inertiaMatrix);

                    // add the part distance offset to the ship inertiaTensor
                    OuterProduct2(position, -part.rb.mass * position, ref productMatrix);
                    KSPUtil.Add(ref tensor, productMatrix);
                }
            }
            return KSPUtil.Diag(tensor);
        }

        public static void GetPotentialTorque(Vessel vessel, out Vector3d pos, out Vector3d neg)
        {
            Dictionary<PartModule, ITorqueProvider> torqueProviders = new Dictionary<PartModule, ITorqueProvider>();
            GetControlParts(vessel, ref torqueProviders);

        }

        /// <summary>
        /// Construct the outer product of two 3-vectors as a 4x4 matrix
        /// DOES NOT ZERO ANY THINGS WOT ARE ZERO OR IDENTITY INNIT
        /// </summary>
        public static void OuterProduct2(Vector3 left, Vector3 right, ref Matrix4x4 m)
        {
            m.m00 = left.x * right.x;
            m.m01 = left.x * right.y;
            m.m02 = left.x * right.z;
            m.m10 = left.y * right.x;
            m.m11 = left.y * right.y;
            m.m12 = left.y * right.z;
            m.m20 = left.z * right.x;
            m.m21 = left.z * right.y;
            m.m22 = left.z * right.z;
        }
        public static void GetControlParts(Vessel vessel, ref Dictionary<PartModule, ITorqueProvider> torqueProviders)
        {
            torqueProviders.Clear();
            foreach (Part part in vessel.Parts)
            {
                foreach (PartModule pm in part.Modules)
                {
                    ITorqueProvider tp = pm as ITorqueProvider;
                    if (tp != null)
                    {
                        torqueProviders.Add(pm, tp);
                    }
                }
            }
        }

        public void UpdateTorque()
        {
            // controlTorque is the maximum amount of torque applied by setting a control to 1.0.
            controlTorque.Zero();
            rawTorque.Zero();
            Vector3d pitchControl = Vector3d.zero;
            Vector3d yawControl = Vector3d.zero;
            Vector3d rollControl = Vector3d.zero;

            Vector3 pos;
            Vector3 neg;
            foreach (var pm in torqueProviders.Keys)
            {
                var tp = torqueProviders[pm];
                CorrectedGetPotentialTorque(tp, out pos, out neg);
                // It is possible for the torque returned to be negative.  It's also possible
                // for the positive and negative actuation to differ.  Below averages the value
                // for positive and negative actuation in an attempt to compensate for some issues
                // of differing signs and asymmetric torque.
                rawTorque.x += (Math.Abs(pos.x) + Math.Abs(neg.x)) / 2;
                rawTorque.y += (Math.Abs(pos.y) + Math.Abs(neg.y)) / 2;
                rawTorque.z += (Math.Abs(pos.z) + Math.Abs(neg.z)) / 2;
            }

            rawTorque.x = (rawTorque.x + PitchTorqueAdjust) * PitchTorqueFactor;
            rawTorque.z = (rawTorque.z + YawTorqueAdjust) * YawTorqueFactor;
            rawTorque.y = (rawTorque.y + RollTorqueAdjust) * RollTorqueFactor;
            controlTorque = rawTorque + adjustTorque;
            //controlTorque = Vector3d.Scale(rawTorque, adjustTorque);
            //controlTorque = rawTorque;

            double minTorque = CONTROLEPSILON;
            if (controlTorque.x < minTorque) controlTorque.x = minTorque;
            if (controlTorque.y < minTorque) controlTorque.y = minTorque;
            if (controlTorque.z < minTorque) controlTorque.z = minTorque;
        }

        /// <summary>
        /// See https://github.com/KSP-KOS/KOS/issues/2814 for why this wrapper around KSP's API call exists.
        /// <para />
        /// </summary>
        void CorrectedGetPotentialTorque(ITorqueProvider tp, out Vector3 pos, out Vector3 neg)
        {
            if (tp is ModuleRCS)
            {
                // The stock call GetPotentialTorque is completely broken in the case of ModuleRCS.  So
                // this replaces it entirely until KSP ever fixes the bug that's been in their
                // bug list forever (probably won't get fixed).
                ModuleRCS rcs = tp as ModuleRCS;
                Part p = rcs.part;

                // This is the list of various reasons this RCS module might 
                // be suppressed right now.  It would be nice if all this
                // stuff flipped one common flag during Update for all the
                // rest of the code to check, but sadly that doesn't seem to
                // be the case and you have to check these things individually:
                if (p.ShieldedFromAirstream || !rcs.rcsEnabled || !rcs.isEnabled ||
                    rcs.isJustForShow || rcs.flameout || !rcs.rcs_active)
                {
                    pos = new Vector3(0f, 0f, 0f);
                    neg = new Vector3(0f, 0f, 0f);
                }
                else
                {
                    // The algorithm here is adapted from code in the MandatoryRCS mod
                    // that had to solve this same problem:

                    // Note the swapping of Y and Z axes to align with "part space":
                    Vector3 rotateEnables = new Vector3(rcs.enablePitch ? 1 : 0, rcs.enableRoll ? 1 : 0, rcs.enableYaw ? 1 : 0);
                    Vector3 translateEnables = new Vector3(rcs.enableX ? 1 : 0, rcs.enableZ ? 1 : 0, rcs.enableY ? 1 : 0);

                    pos = new Vector3(0f, 0f, 0f);
                    neg = new Vector3(0f, 0f, 0f);
                    for (int i = rcs.thrusterTransforms.Count - 1; i >= 0; --i)
                    {
                        Transform rcsTransform = rcs.thrusterTransforms[i];

                        // Fixes github issue #2912:  As of KSP 1.11.x, RCS parts now use part variants.  To keep kOS
                        // from counting torque as if the superset of all variant nozzles were present, the ones not
                        // currently active have to be culled out here, since KSP isn't culling them out itself when
                        // it populates ModuleRCS.thrusterTransforms:
                        if (!rcsTransform.gameObject.activeInHierarchy)
                            continue;

                        Vector3 rcsPosFromCoM = rcsTransform.position - Vessel.CurrentCoM;
                        Vector3 rcsThrustDir = rcs.useZaxis ? -rcsTransform.forward : rcsTransform.up;
                        float powerFactor = rcs.thrusterPower * rcs.thrustPercentage * 0.01f;
                        // Normally you'd check for precision mode to nerf powerFactor here,
                        // but kOS doesn't obey that.
                        Vector3 thrust = powerFactor * rcsThrustDir;
                        Vector3 torque = Vector3d.Cross(rcsPosFromCoM, thrust);
                        Vector3 transformedTorque = Vector3.Scale(Vessel.ReferenceTransform.InverseTransformDirection(torque), rotateEnables);
                        pos += Vector3.Max(transformedTorque, Vector3.zero);
                        neg += Vector3.Min(transformedTorque, Vector3.zero);
                    }
                }
            }
            else if (tp is ModuleReactionWheel)
            {
                // Although ModuleReactionWheel *mostly* works, the stock version ignores
                // the authority limiter slider.  It would have been possible to just take
                // the result it gives and multiply it by the slider, but that relies on
                // stock KSP never fixing it themselves and thus kOS would end up double-
                // applying that multiplitation.  To avoid that, it seems better to just
                // make the entire thing homemade from scratch for now so if KSP ever fixes it
                // on their end that doesn't break it on kOS's end:
                ModuleReactionWheel wheel = tp as ModuleReactionWheel;

                if (!wheel.moduleIsEnabled || wheel.wheelState != ModuleReactionWheel.WheelState.Active || wheel.actuatorModeCycle == 2)
                {
                    pos = new Vector3(0f, 0f, 0f);
                    neg = new Vector3(0f, 0f, 0f);
                }
                else
                {
                    float nerf = wheel.authorityLimiter / 100f;
                    pos = new Vector3(nerf * wheel.PitchTorque, nerf * wheel.RollTorque, nerf * wheel.YawTorque);
                    neg = -1 * pos;
                }
            }
            else
            {
                tp.GetPotentialTorque(out pos, out neg);
            }
        }
    }
}
