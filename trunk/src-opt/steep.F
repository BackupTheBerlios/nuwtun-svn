C
C Steepest descent algorithm
C Author: Praveen. C, TIFR-CAM, Bangalore 
C Date  : 5 Dec, 2008
C
C f(:) contains all function evaluations, including those discarded for
C updating step size.
C fit(:) contains function values at each iteration
C
      program main
      implicit none
      include '../src-adj/header/refval.h'
      integer NDMAX, ITMAX
      real    GTOL, OTOL
      parameter(NDMAX=100, ITMAX=100)
      integer nfeval, ngeval
      common/eval/nfeval, ngeval

      integer nd, it, i, itm, iter
      real    x(0:ITMAX,NDMAX), f(0:ITMAX), g(0:ITMAX,NDMAX)
      real    fit(0:ITMAX)
      real    step0, step(0:ITMAX)
      real    gn(0:ITMAX)
      integer icftyp
      real    df1, df2, df3

      write(*,10)
      write(*,*)'    STEEPEST DESCENT OPTIMIZATION'
      write(*,10)

      if(iargc().ne.1)then
         print*,'steep: Specify cost function type'
         stop
      endif

c     Read optimization parameters from a file
      call readparam(nd, step0, itm, gtol, otol) 
      if(itm.gt.ITMAX)then
         print*,'itm > ITMAX, increase ITMAX'
         stop
      endif

c     Reset function/gradient counter
      nfeval = 0
      ngeval = 0

c     Set cost function type
      write(*,*)
      call sicftyp(icftyp)
      write(*,*)

      it       = 0
      open(10, file='shape0.dat', status='old')
      read(10,*)(x(it,i),i=1,nd)
      close(10)
      step(it) = step0
c     Compute cost function and its gradient
      call CostFunVal(icftyp, nd, x(it,:), f(it))
      call CostGradVal(icftyp, nd, x(it,:), g(it,:), gn(it))
      write(*,*)' Iteration number ', it
      write(*,*)' Cost fun  =', f(it)
      write(*,*)' Grad norm =', gn(it)
      write(*,*)
      write(*,10)
      fit(it) = f(it)

      iter = 0

c     Beginning of iterations
      do while(it.lt.itm .and. gn(it).gt.GTOL)
c        Update design variables
         do i=1,nd
             x(it+1,i) = x(it,i) - step(it)*g(it,i)/gn(it)
         enddo
c        Increment iteration counter
         it = it + 1
c        Compute cost function and its gradient
         call CostFunVal(icftyp, nd, x(it,:), f(it))
c        Compute step size
         if( f(it).le.f(it-1) )then
            iter = iter + 1
            fit(iter) = f(it)
            call CostGradVal(icftyp, nd, x(it,:), g(it,:), gn(it))
            write(*,*)
            write(*,*)' Function evaluation ', it
            write(*,*)' Cost fun  =', f(it)
            write(*,*)' Grad norm =', gn(it)
            write(*,*)
            write(*,10)
            step(it) = step(it-1)
         else ! reduce step and reset to previous iteration
            write(*,*)
            write(*,*)' Function evaluation ', it
            write(*,*)' Cost fun  =', f(it)
            write(*,*)
            write(*,*)'*** Function did not decrease ***'
            write(*,*)'*** Resetting to prev iter    ***'
            write(*,*)'*** Reducing step size        ***'
            write(*,*)
            write(*,10)
            step(it)    = 0.5*step(it-1)
            f(it)       = f(it-1)
            x(it, 1:nd) = x(it-1, 1:nd)
            g(it, 1:nd) = g(it-1, 1:nd)
            gn(it)      = gn(it-1)
         endif
c        Check if we must stop
         if(iter.gt.3)then
            df1 = abs( fit(iter ) - fit(iter-1)  )
            df2 = abs( fit(iter-1) - fit(iter-2) )
            df3 = abs( fit(iter-2) - fit(iter-3) )
            if(df1.lt.OTOL .and. 
     1         df2.lt.OTOL .and. 
     2         df3.lt.OTOL) then
               write(*,*)
               write(*,*)'Objective function did not decrease'
               write(*,*)'sufficiently for 3 iterations'
               write(*,*)
               goto 123
            endif
         endif
      enddo

123   continue

      write(*,*)
      write(*,*)'Number of iterations           =',iter
      write(*,*)'Number of function evaluations =',nfeval
      write(*,*)'Number of gradient evaluations =',ngeval
      write(*,*)

c     save iteration history
      open(20, file='opthist.dat')
      do i=0,it
         write(20,20) i, f(i), gn(i), step(i)
      enddo
      close(20)

10    format('-------------------------------------------------------')
20    format(i6,3e12.5)

      stop
      end
C
C     Read optimization parameters from file steep.in
C
      subroutine readparam(nd, step0, itm, gtol, otol) 
      implicit none
      integer nd, itm
      real    step0, gtol, otol

      open(30, file='steep.in', status='old')
      read(30,*) nd
      read(30,*) step0
      read(30,*) itm
      read(30,*) gtol
      read(30,*) otol
      close(30)

      print*
      print*,'Number of design variables =', nd
      print*,'Initial step size          =', step0
      print*,'Max number of iterations   =', itm
      print*,'Gradient tolerance         =', gtol
      print*,'Objectiv tolerance         =', otol
      print*

      end

C
C     Computes cost function
C
      subroutine CostFunVal(icftyp, nd, x, f)
      implicit none
      include '../src-adj/header/refval.h'
      integer nfeval, ngeval
      common/eval/nfeval, ngeval
      integer icftyp, nd
      real    x(*), f

      integer i, j
      real    cl, cd, apgint, cost
      character*32 str

      print*,'Design variables:'
      write(*,*)(x(i),i=1,nd)

c     write parameters to file
      open(10, file='shape.dat')
      write(10,'(e20.10)')(x(i),i=1,nd)
      close(10)
      print*,'Deforming grid ...'
      call system("deform > def.log")

c     run flow solver
      call system("rm -f fort.19")
      print*,'Running flow solver ...'
      call system("$NUWTUN_HOME/src-flo/nuwtun_flo < flo.in > flo.log")

c     Read current values
      open(10, file='fort.19', status='old')
      read(10,*)
      read(10,*)
      read(10,*) str, cl
      read(10,*) str, cd
      read(10,*) str, apgint
      close(10)

      print*,'cl     =',cl
      print*,'cd     =',cd
      print*,'apgrad =',apgint

c     If first computation, set reference values
c     Create refval.dat file, needed by adjoint solver
      if(nfeval.eq.0)then
        clref = cl
        cdref = cd
        apref = apgint
        call system("cp fort.19 refval.dat")
      endif

      call costfun(icftyp, cl, cd, apgint, cost)
      f = cost

      nfeval = nfeval + 1

      end
C
C     Computes cost gradient
C
      subroutine CostGradVal(icftyp, nd, x, g, gn)
      implicit none
      integer nfeval, ngeval
      common/eval/nfeval, ngeval
      integer icftyp, nd
      real    x(*), g(*), gn

      integer i, j
      character*80 ct

c     run adjoint solver
      call getarg(1, ct)
      print*,'Running adjoint flow solver for ',TRIM(ct)
      call system("nuwtun_adj "//TRIM(ct)//" < flo.in > adj.log")
      print*,'Running adjoint grid solver ...'
      call system("deform_adj > def_adj.log")

      open(10, file='gradient.dat', status='old')
      do i=1,nd
         read(10,*) j, g(i)
      enddo
      close(10)

      print*,'Gradient:'
      write(*,*)(g(i),i=1,nd)

c     Norm of gradient
      gn = 0.0
      do i=1,nd
         gn = gn + g(i)**2
      enddo
      gn = sqrt(gn)

      ngeval = ngeval + 1

      end
