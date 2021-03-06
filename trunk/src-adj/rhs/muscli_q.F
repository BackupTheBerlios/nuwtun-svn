      SUBROUTINE MUSCLI_Q (IDIM, JDIM, KDIM, K, IPSTRT, IPEND,
     1                    Q, QB, DQP, DQPB, DQM, DQMB, QP, QPB, QM, QMB,
     2                    IBCDAT, NBCS, IORDER, LIMIT, RKAP)
C
C Routine to do MUSCL interpolation in the I direction. This routine 
C interpolates for Q(+,-) on the I faces for i = ipstrt-1, ipend by 
C j = 2, jdim on the current K plane.  (IPSTRT and IPEND refer to cell centers, 
C therefore the interfaces are from IPSTRT-1 to IPEND.) This allows for greater 
C vectorization and also minimizes intermediate storage to a cross section.  
C
C Note the beginning and ending indices of the arrays.
C
C This routine is organized as follows:
C     0. Set up beginning/ending indices for first and second order sections
C     1. Calculate Q(+,-)
C        a. First order
C        b. Second order
C           i.   Calculate delta(Q)
C           ii.  Limit delta(Q)
C           iii. Construct Q(+,-)
C     2. Correct wall values of Q(+,-)
C
C IDIM,JDIM,KDIM : Dimensions of current block
C K              : K Plane to do interpolation on
C IPSTRT         : I Plane (cell center) to start calculations at 
C                  (Minimum Value: 2)
C IPEND          : I Plane (cell center) to end caclulations at
C                  (Maximum Value: IDIM)
C Q              : Primitive variables at cell centers
C DQP,DQM        : Storage for delta q = q(i) - q(i-1) and
C                  for the higher order interpolant to be added
C                  to the first order scheme to create QP,QM
C QP,QM          : Q(+),Q(-) at a cell interface for MUSCL scheme
C IBCDAT         : Data controlling boundary conditions:
C                  IBCDAT(1,ibc) = Boundary Condition Type
C                         2      = Direction (1=i, 2=j, 3=k)
C                         3      = i(1 or idim)
C                         4      = istrt
C                         5      = iend
C                         6      = jstrt
C                         7      = jend
C                         8      = kstrt
C                         9      = kend
C                         10     = profile identifier
C NBCS           : Number of boundary conditions for current block
C IORDER         : Order of MUSCL interpolation for I direction 
C                  IORDER = 1 first order
C                         = 2 second order (or 'third' order)
C LIMIT          : Limiter to use for MUSCL interpolation
C RKAP           : Kappa to use in MUSCL interpolation
C
      include '../../src-flo/header/common.h'
C
      DIMENSION Q     (0:JDIM+2,0:KDIM+2,0:IDIM+2,NQ),
     1          DQP   (IPSTRT-2:IPEND+1,2:JDIM,NQ),
     2          DQM   (IPSTRT-2:IPEND+1,2:JDIM,NQ),
     3          QP    (IPSTRT-1:IPEND,2:JDIM,NQ), 
     4          QM    (IPSTRT-1:IPEND,2:JDIM,NQ),
     5          QB    (0:JDIM+2,0:KDIM+2,0:IDIM+2,NQ),
     6          DQPB  (IPSTRT-2:IPEND+1,2:JDIM,NQ),
     7          DQMB  (IPSTRT-2:IPEND+1,2:JDIM,NQ),
     8          QPB   (IPSTRT-1:IPEND,2:JDIM,NQ), 
     9          QMB   (IPSTRT-1:IPEND,2:JDIM,NQ) 
C
      DIMENSION IBCDAT(10,NBCS)
C
C Local Storage
C
      LOGICAL   DOFRST,
     1          DOSCND
C
C 0.  Set up beginning/ending indices for first and second order sections
C
      LFOBEG = 0
      LFOEND = -1
      LSOBEG = 1
      LSOEND = NQ
      DOFRST = .FALSE.
      DOSCND = .TRUE.
C
      IF (IORDER .EQ. 1) THEN
         LFOBEG = 1
         LFOEND = NQ
         LSOBEG = 0
         LSOEND = -1
         DOFRST = .TRUE.
         DOSCND = .FALSE.
      ELSE IF (FOTURB) THEN
         LFOBEG = 6
         LFOEND = NQ
         LSOBEG = 1
         LSOEND = 5
         DOFRST = .TRUE.
         DOSCND = .TRUE.
      END IF
C
C 1.  Calculate Q(+,-)
C     Loop over j,i formulating q(extrapolated) - inner loop is over j for 
C     maximum vectorization for 2d and planar oriented algorithms. This also 
C     results in unit stride. I is stored first so that successive values of 
C     i (i = 1,2,3...) are stored together for limiting.
C
C 1-a. First Order
C
C
C 1-b. Second Order or Third Order
C 1-b-i. Calculate delta(Q)
C        Calculate delta(q(i)) = q(i+1) - q(i) to formulate q(extrapolated) 
C        using limiting.
C
      IF (DOSCND) THEN
         DO 230 L = LSOBEG, LSOEND
            DO 220 I = IPSTRT - 2, IPEND + 1
               DO 200 J = 2, JDIM
                  DQP(I,J,L) = Q(J,K,I+1,L) - Q(J,K,I,L)
  200          CONTINUE
  220       CONTINUE
  230    CONTINUE
C
C     Set delta(q) to 2*delta(q) to adjust for the wall boundary condition 
C     being on the wall rather than at a cell center.
C     Set delta(q) = 0 on wall for wall function to adjust for grid spacing.
C
         DO 300 IBC = 1, NBCS
            IBCTYP = IBCDAT(1,IBC)
            IDIR   = IBCDAT(2,IBC)
            IF ( IDIR .EQ. 1 .AND.
     1           ( IBCTYP .EQ. ITAN  .OR. IBCTYP .EQ. IWALL .OR.
     2             IBCTYP .EQ. IWALFN ) ) THEN
               INROUT = IBCDAT(3,IBC)
               JSTRT  = IBCDAT(6,IBC)
               JEND   = IBCDAT(7,IBC)
               KSTRT  = IBCDAT(8,IBC)
               KEND   = IBCDAT(9,IBC)
               IF (INROUT .EQ. 1) THEN
                  IBCPT = 1
               ELSE
                  IBCPT = IDIM
               ENDIF
               IF (IBCTYP .EQ. IWALFN)THEN
                  FACTR = 0.E0
               ELSE
                  FACTR = 2.E0
               ENDIF
               IF (IBCPT .GE. IPSTRT-1 .AND. IBCPT .LE. IPEND .AND.
     1                 K .GE. KSTRT    .AND.     K .LE. KEND      ) THEN
                  DO 290 L = LSOBEG, LSOEND
                     DO 280 J = JSTRT, JEND
                        DQP(IBCPT,J,L) = FACTR * DQP(IBCPT,J,L)
  280                CONTINUE
  290             CONTINUE
               ENDIF
            ENDIF
  300    CONTINUE
C
C 1-b-ii.  Limit delta(Q)
C     Limit from i = ipstrt-2 to i = ipend+1 by j = 2 to j = jdim times.
C     DQP is used to pass in the values of delta q.
C     The values of the limited deltas are stored in DQP and DQM.
C     These values not valid at the endpoints of each i line, but are
C     calculated here to maximize vectorization on a ixj plane.
C
C
C 1-b-iii. Construct Q(+,-)
C     Calculate q(extrapolated,i+1/2) from q and the limited values of delta(q)
C
      ENDIF
C
C 2.  Correct wall values of Q(+,-)
C     Fix boundary values of q(extrapolated) due to boundary conditions
C     for either the first order or higher order scheme.
C     WALL boundary condition.  Reset QP(wall)=QM(wall)=Q(wall)
C
C
C BEGIN BACKWARD SWEEP
C
C 2.  Correct wall values of Q(+,-)
C     Fix boundary values of q(extrapolated) due to boundary conditions
C     for either the first order or higher order scheme.
C     WALL boundary condition.  Reset QP(wall)=QM(wall)=Q(wall)
C
      DO 1800 IBC = 1, NBCS
         IBCTYP = IBCDAT(1,IBC)
         IDIR   = IBCDAT(2,IBC)
         IF ( IDIR .EQ. 1 .AND.
     1        ( IBCTYP .EQ. ITAN  .OR. IBCTYP .EQ. IWALL .OR.
     2          IBCTYP .EQ. IWALFN ) ) THEN
            INROUT = IBCDAT(3,IBC)
            JSTRT  = IBCDAT(6,IBC)
            JEND   = IBCDAT(7,IBC)
            KSTRT  = IBCDAT(8,IBC)
            KEND   = IBCDAT(9,IBC)
            IF (INROUT .EQ. 1) THEN
               IQPM  = 1
               IBCPT = 1
            ELSE
               IQPM  = IDIM
               IBCPT = IDIM + 1
            ENDIF
            IF (IBCPT .GE. IPSTRT-1 .AND. IBCPT .LE. IPEND .AND.
     1              K .GE. KSTRT    .AND.     K .LE. KEND        ) THEN
               DO 1790 L = 1, NQ
                  DO 1780 J = JSTRT, JEND
                     QB(J,K,IBCPT,L) = QB(J,K,IBCPT,L) + QPB(IQPM,J,L)
     1                                                 + QMB(IQPM,J,L)
                     QPB(IQPM,J,L)   = 0.0
                     QMB(IQPM,J,L)   = 0.0
 1780             CONTINUE
 1790          CONTINUE
            ENDIF
         ENDIF
 1800 CONTINUE
C
C 1-b. Second Order or Third Order
C
      IF (DOSCND) THEN
C
C 1-b-iii. Construct Q(+,-)
C     Calculate q(extrapolated,i+1/2) from q and the limited values of delta(q)
C
         DO 1380 L = LSOBEG, LSOEND
            DO 1370 I = IPSTRT - 1, IPEND
               DO 1360 J = 2, JDIM
                  QB(J, K, I, L)   = QB(J, K, I, L) + QMB(I, J, L)
                  DQMB(I, J, L)    = DQMB(I, J, L) + QMB(I, J, L)
                  QMB(I, J, L)     = 0.0E0
                  QB(J, K, I+1, L) = QB(J, K, I+1, L) + QPB(I, J, L)
                  DQPB(I, J, L)    = DQPB(I, J, L) + QPB(I, J, L)
                  QPB(I, J, L)     = 0.0E0
 1360          CONTINUE
 1370       CONTINUE
 1380    CONTINUE
C
C 1-b-ii.  Limit delta(Q)
C     Limit from i = ipstrt-2 to i = ipend+1 by j = 2 to j = jdim times.
C     DQP is used to pass in the values of delta q.
C     The values of the limited deltas are stored in DQP and DQM.
C     These values not valid at the endpoints of each i line, but are
C     calculated here to maximize vectorization on a ixj plane.
C
         NPTS = ( IPEND - IPSTRT + 4 ) * ( JDIM - 1 )
         CALL LIMITR_Q (NPTS, DQP, DQPB, DQM, DQMB, LIMIT, RKAP, 
     1                  LSOBEG, LSOEND, IERROR)

C
C     Set delta(q) to 2*delta(q) to adjust for the wall boundary condition 
C     being on the wall rather than at a cell center.
C     Set delta(q) = 0 on wall for wall function to adjust for grid spacing.
C
         DO 1300 IBC = 1, NBCS
            IBCTYP = IBCDAT(1,IBC)
            IDIR   = IBCDAT(2,IBC)
            IF ( IDIR .EQ. 1 .AND.
     1           ( IBCTYP .EQ. ITAN  .OR. IBCTYP .EQ. IWALL .OR.
     2             IBCTYP .EQ. IWALFN ) ) THEN
               INROUT = IBCDAT(3,IBC)
               JSTRT  = IBCDAT(6,IBC)
               JEND   = IBCDAT(7,IBC)
               KSTRT  = IBCDAT(8,IBC)
               KEND   = IBCDAT(9,IBC)
               IF (INROUT .EQ. 1) THEN
                  IBCPT = 1
               ELSE
                  IBCPT = IDIM
               ENDIF
               IF (IBCTYP .EQ. IWALFN)THEN
                  FACTR = 0.E0
               ELSE
                  FACTR = 2.E0
               ENDIF
               IF (IBCPT .GE. IPSTRT-1 .AND. IBCPT .LE. IPEND .AND.
     1                 K .GE. KSTRT    .AND.     K .LE. KEND      ) THEN
                  DO 1290 L = LSOBEG, LSOEND
                     DO 1280 J = JSTRT, JEND
                        DQPB(IBCPT, J, L) = FACTR*DQPB(IBCPT, J, L)
 1280                CONTINUE
 1290             CONTINUE
               ENDIF
            ENDIF
 1300    CONTINUE
C
C 1-b-i. Calculate delta(Q)
C        Calculate delta(q(i)) = q(i+1) - q(i) to formulate q(extrapolated) 
C        using limiting.
C
         DO 1230 L = LSOBEG, LSOEND
            DO 1220 I = IPSTRT - 2, IPEND + 1
               DO 1200 J = 2, JDIM
                  QB(J, K, I+1, L) = QB(J, K, I+1, L) + DQPB(I, J, L)
                  QB(J, K, I, L)   = QB(J, K, I, L) - DQPB(I, J, L)
                  DQPB(I, J, L)    = 0.0
 1200          CONTINUE
 1220       CONTINUE
 1230    CONTINUE

      ENDIF
C
C 1-a. First Order
C
      IF (DOFRST) THEN
         DO 1130 L = LFOBEG, LFOEND
            DO 1120 I = IPSTRT - 1, IPEND
               DO 1110 J = 2, JDIM
                  QB(J, K, I, L)   = QB(J, K, I, L) + QMB(I, J, L)
                  QMB(I, J, L)     = 0.0
                  QB(J, K, I+1, L) = QB(J, K, I+1, L) + QPB(I, J, L)
                  QPB(I, J, L)     = 0.0
 1110          CONTINUE
 1120       CONTINUE
 1130    CONTINUE
      ENDIF

      RETURN
      END
