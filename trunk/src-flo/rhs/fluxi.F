C
C     This file is part of NuWTun, see <http://nuwtun.berlios.de>, and was
C     originally taken from ISAAC Version 4.2, release date October 2001. 
C     This file may have been modified; for a list of changes, see the 
C     changes.txt file in the docs directory and the subversion log.
C
C     Portions Copyright (C) 2001 Joseph H. Morrison
C
C     This code is part of ISAAC.
C
C     This program is distributed under the terms of the ISAAC Public Source
C     License. This program is distributed WITHOUT ANY WARRANTY; without
C     even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
C     PURPOSE. 
C
C     You should have received a copy of the ISAAC Public Source License
C     with this program. If you did not, you may get a copy of the license
C     at <http://isaac-cfd.sourceforge.net>
C
      SUBROUTINE FLUXI (IDIM, JDIM, KDIM, IPSTRT, IPEND, MXSECT,
     1                  Q, PROPS, NPPTS, S, VOL, 
     2                  RES, DQP, DQM, QP, QM, TAU, F, FM, STEMP,
     3                  IBCDAT, NBCS, IORDER, LIMIT, RKAP, IFLUX, 
     4                  VISCOS, IMODEL)
C
C     Routine to calculate the contribution to the residual from the
C     i direction.  This routine is used for either the 
C     time dependent calculation or the marching calculation.  
C
C
C     IDIM,JDIM,KDIM : Dimensions of current block
C     IPSTRT         : I Plane (cell center) to start calculations at 
C                      (Minimum Value: 2)
C     IPEND          : I Plane (cell center) to end caclulations at
C                      (Maximum Value: IDIM)
C     MXSECT         : Maximum size of any (ixj, jxk or ixk)
C                      (used in dimensioning temporary space used for 
C                       calculating q(+,-) and f.
C     Q              : Primitive variables at cell centers
C     PROPS          : Properties at cell centers
C                      PROPS(1) = molecular viscosity
C                      PROPS(2) = turbulent eddy viscosity 
C                      PROPS(3) = Y+
C     NPPTS          : Number of points at which PROPS are stored.  This allows
C                      the storage of PROPS for viscous flows and the avoidance
C                      of the additional storage for inviscid flows.
C     S              : Metrics
C     VOL            : Cell volumes
C     RES            : Residual
C     DQP,DQM        : Storage for delta q = q(i) - q(i-1)
C     QP,QM          : Q(+),Q(-) at a cell interface for MUSCL scheme
C     TAU            : Storage for Reynolds stresses at interfaces
C     F,FM           : Fluxes at cell interfaces -
C                      if Flux Difference Splitting then F = Flux
C                      if Flux Vector Splitting then F = Fplus, FM = Fminus
C     STEMP          : Storage for metrics passed to flux evaluation routine.
C     IBCDAT         : Data controlling boundary conditions
C     NBCS           : Number of boundary conditions for current block
C     IORDER         : Order of MUSCL interpolation for I direction 
C                      IORDER = 1 first order
C                             = 2 second order (or 'third' order)
C     LIMIT          : Limiter to use for MUSCL interpolation
C     RKAP           : Kappa to use in MUSCL interpolation
C     IFLUX          : Flux evaluation scheme
C     VISCOS         : Logical for viscous (TRUE) or inviscid (FALSE) flow
C     IMODEL         : Turbulence model
C
      include '../header/common.h'
C
      DIMENSION Q     (0:JDIM+2,0:KDIM+2,0:IDIM+2,NQ),
     1          PROPS (0:JDIM+2,0:KDIM+2,0:IDIM+2,NP),
     2          S     (0:JDIM+1,0:KDIM+1,0:IDIM+1,4,3),
     3          VOL   (0:JDIM+1,0:KDIM+1,0:IDIM+1)
C
      DIMENSION RES   (JDIM+1,KDIM+1,IPSTRT-1:IPEND+1,NF),
     1          DQP   (MXSECT,NQ), 
     2          DQM   (MXSECT,NQ),
     3          QP    (MXSECT,NQ), 
     4          QM    (MXSECT,NQ),
     5          TAU   (MXSECT,6),
     6          F     (IPSTRT-1:IPEND,2:JDIM,NF), 
     7          FM    (IPSTRT-1:IPEND,2:JDIM,NF), 
     8          STEMP (IPSTRT-1:IPEND,2:JDIM,3)
C
      DIMENSION IBCDAT(10,NBCS)
C
      DIMENSION IMODEL(NMDL)
C
      LOGICAL   VISCOS
C
      ITURB = IMODEL(1)
C
C     Loop over K calculating Q(+,-), F(Q(+,-)) and updating the Residual.
C
      DO 500 K = 2, KDIM
C
C     Inviscid Residuals
C
         CALL MUSCLI (IDIM, JDIM, KDIM, K, IPSTRT, IPEND,
     1                Q, DQP, DQM, QP, QM,
     2                IBCDAT, NBCS, IORDER, LIMIT, RKAP)
C
C     Calculate the fluxes from q(plus) and q(minus).  Pass only
C     the appropriate metrics from the current direction.
C
         DO 120 I = IPSTRT - 1, IPEND
            DO 110 J = 2, JDIM
               DO 100 L = 1, 3
                  STEMP(I,J,L) = S(J,K,I,L,1)
  100          CONTINUE
  110       CONTINUE
  120    CONTINUE
         NPTS = (IPEND - IPSTRT + 2) * (JDIM - 1)
C
C     Flux Difference Splitting
C
         IF (IFCHAR(IFLUX,1) .EQ. IFDS) THEN
C
C     Add the flux contributions to the residual.
C
            CALL FDS (IFLUX, ITURB, NPTS, QP, QM, STEMP, F)
C
            DO 180 L = 1, NF
               DO 160 I = IPSTRT, IPEND
                  DO 140 J = 2, JDIM
                     RES(J,K,I,L) = RES(J,K,I,L) + 
     1                              ( F(I,J,L)   * S(J,K,I,4,1) -
     2                                F(I-1,J,L) * S(J,K,I-1,4,1) )
  140             CONTINUE
  160          CONTINUE
  180       CONTINUE
         ENDIF
C
C     Viscous Residuals
C
         IF ( VISCOS ) THEN
C
C     Calculate the derivatives and averages of stored variables at the
C     interfaces.
C     Temporary variables passed to the viscous flux evaluation routine:
C         QP    for Q      (variables at interface)
C         FM    for PROPSI (properties at interface)
C               NOTE: This works properly only as long as NP <= NQ
C         QM    for DQDX   (derivatives of Q in x direction at interface)
C         DQP   for DQDY   (derivatives of Q in y direction at interface)
C         DQM   for DQDZ   (derivatives of Q in z direction at interface)
C     Temporary variables used internally in DELQ:
C         F(2-NQ) for SI (STEMP is dimensioned incorrectly to be used for
C                     the averaged metrics in the J direction.  F is large
C                     enough to provide the necessary space.  Do not use
C                     F for anything else in this call).
C         F(1)    for VOLAUX 
C
            CALL DELQI (IDIM, JDIM, KDIM, IPSTRT, IPEND, K,
     1                  Q, PROPS, S, VOL, IBCDAT, NBCS,
     2                  F(1,2,2), F(1,2,1), QP, FM, QM, DQP, DQM)
C
C     Viscous Terms 
C
            CALL FVIS(IMODEL, NPTS, QP, FM, QM, DQP, DQM, STEMP, TAU, F)
C
C Wall Functions - if not integrating to the wall
C
            IF ( IFWALF ) THEN
C
C Loop over WALL FUNCTION boundary conditions for I faces - Calculate 
C flux boundary conditions for Wall Functions 
C
               DO 300 IBC = 1, NBCS
                  IBCTYP = IBCDAT(1,IBC)
                  IDIR   = IBCDAT(2,IBC)
                  ISTRT  = IBCDAT(4,IBC)
                  IEND   = IBCDAT(5,IBC)
                  IF (IBCTYP .EQ. IWALFN .AND. IDIR .EQ. 1) THEN
C
                     INROUT = IBCDAT(3,IBC)
                     JSTRT  = MAX (IBCDAT(6,IBC), 2)
                     JEND   = MIN (IBCDAT(7,IBC), JDIM)
C
                     IF (INROUT .EQ. 1) THEN
                        IN     = 2
                        IM     = 1
                        IW     = 1
                        IBC2   = 0
                        SGNM   = 1.E0
                     ELSE
                        IN     = IDIM
                        IM     = IDIM
                        IW     = IDIM
                        IBC2   = IDIM + 2
                        SGNM   = - 1.E0
                     ENDIF
C
C Modify viscous wall fluxes - set all viscous fluxes to zero then correct
C
                     DO 270 L = 1, NQ
                        DO 260 J = JSTRT, JEND
                           F(IW,J,L) = 0.E0
  260                   CONTINUE
  270                CONTINUE
C
                     DO 280 J = JSTRT, JEND
C
C Non-dimensionalize variables for flux terms, SGNM to account for inner
C or outer end of coordinate 
C
                        TAUW   = PROPS(J,K,IBC2,ITQTAU)*SGNM*FSMACH/RE
                        QW     = PROPS(J,K,IBC2,ITQDOT)*SGNM*FSMACH/RE
C
C Tangency vector => aligned with parallel velocity at adjoining cell center
C Note: SGNM used in specification of unit vector parallel to wall in BCWALF
C       cancels and is removed here for computational efficiency.
C
                        UDOTN  = Q(J,K,IN,2) * S(J,K,IM,1,IDIR) +
     1                           Q(J,K,IN,3) * S(J,K,IM,2,IDIR) +
     2                           Q(J,K,IN,4) * S(J,K,IM,3,IDIR)
                        UPN    = Q(J,K,IN,2) - UDOTN * S(J,K,IM,1,IDIR)
                        VPN    = Q(J,K,IN,3) - UDOTN * S(J,K,IM,2,IDIR)
                        WPN    = Q(J,K,IN,4) - UDOTN * S(J,K,IM,3,IDIR)
                        UPARN  = SQRT( UPN*UPN + VPN*VPN + WPN*WPN )
                        UPARN  = MAX ( UPARN, RSMALL )
C
C Calculate the viscous wall flux terms
C
                        F(IW,J,2) = TAUW * UPN / UPARN
                        F(IW,J,3) = TAUW * VPN / UPARN
                        F(IW,J,4) = TAUW * WPN / UPARN
                        F(IW,J,5) = - QW
  280                CONTINUE
                  ENDIF
  300          CONTINUE
            ENDIF
C
C     Add fluxes to residual
C
            DO 380 L = 1, NF
               DO 360 I = IPSTRT, IPEND
                  DO 340 J = 2, JDIM
                     RES(J,K,I,L) = RES(J,K,I,L) - 
     1                              ( F(I,J,L)   * S(J,K,I,4,1) - 
     2                                F(I-1,J,L) * S(J,K,I-1,4,1) )
  340             CONTINUE
  360          CONTINUE
  380       CONTINUE
C
         ENDIF
  500 CONTINUE
C
C     Finished with i direction residual computation.
C
      RETURN
      END
