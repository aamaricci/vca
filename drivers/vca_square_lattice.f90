program vca_test
  USE SCIFOR
  USE DMFT_TOOLS
  USE MPI
  USE VCA
  !
  implicit none
  integer                                         :: Nlso,Nsys
  integer                                         :: ilat,jlat
  integer                                         :: iloop
  integer                                         :: ix,iy,ik
  logical                                         :: converged
  real(8)                                         :: wband

  !The local hybridization function:
  real(8),dimension(:,:),allocatable              :: Tsys,Tref,Vmat,Htb,Mmat,dens
  real(8),allocatable,dimension(:)                :: wm,wr
  complex(8)                                      :: iw
  complex(8),allocatable,dimension(:,:,:,:,:,:,:) :: Gmats,Greal
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: t_prime
  complex(8),allocatable,dimension(:,:,:,:,:,:,:) :: h_k
  complex(8),allocatable,dimension(:,:,:,:,:,:,:) :: t_k
  character(len=16)                               :: finput
  real(8)                                         :: ts
  integer                                         :: Nx,Ny,Lx,Ly,Rx,Ry
  integer                                         :: unit
  integer                                         :: comm,rank
  logical                                         :: master,wloop,wmin
  integer                                         :: nloop
   !FIX!!!!!!!!!!!!!!!
  real(8)                                         :: mu,t,t_var,mu_var
  real(8),dimension(:),allocatable                :: ts_array,omega_array
  integer,dimension(1)                            :: min_loc
  complex(8),allocatable,dimension(:,:,:,:,:)     :: gfmats_periodized ![Nspin][Nspin][Norb][Norb][Lmats]
  complex(8),allocatable,dimension(:,:,:,:,:)     :: gfreal_periodized ![Nspin][Nspin][Norb][Norb][Lreal]
  complex(8),allocatable,dimension(:,:,:,:,:)     :: impSmats_periodized         ![Nspin][Nspin][Norb][Norb][Lmats]
  complex(8),allocatable,dimension(:,:,:,:,:)     :: impSreal_periodized         ![Nspin][Nspin][Norb][Norb][Lreal]
  complex(8),allocatable,dimension(:,:,:,:,:)     :: gtest_mats,gtest_Real,sigmatest_mats,sigmatest_real
  real(8),allocatable,dimension(:,:)              :: kgrid_test

  call init_MPI()
  comm = MPI_COMM_WORLD
  call StartMsg_MPI(comm)
  rank = get_Rank_MPI(comm)
  master = get_Master_MPI(comm)

  call parse_cmd_variable(finput,"FINPUT",default='inputVCA.conf')
  call parse_input_variable(ts,"ts",finput,default=1d0)
  call parse_input_variable(Nx,"Nx",finput,default=2,comment="Number of sites along X")
  call parse_input_variable(Ny,"Ny",finput,default=2,comment="Number of sites along Y")
  call parse_input_variable(nloop,"NLOOP",finput,default=100)
  call parse_input_variable(wloop,"WLOOP",finput,default=.false.)
  call parse_input_variable(wmin,"wmin",finput,default=.false.,comment="T: includes global minimization")
  !
  call vca_read_input(trim(finput),comm)
  !if(Norb/=1)stop "Norb != 1"
  !if(Nspin/=1)stop "Nspin != 1"
  !
  !
  Nlso = (Nx**Ndim)*Norb*Nspin
  Nlat=Nx**Ndim
  Ny=Nx
  !
  t_var=1.0d0
  t=1.0d0
  mu=0.d0
  mu_var=0.d0

  !Add DMFT CTRL Variables:
  call add_ctrl_var(Nlat,"NLAT")
  call add_ctrl_var(Norb,"norb")
  call add_ctrl_var(Nspin,"nspin")
  call add_ctrl_var(beta,"beta")
  call add_ctrl_var(xmu,"xmu")
  call add_ctrl_var(wini,'wini')
  call add_ctrl_var(wfin,'wfin')
  call add_ctrl_var(eps,"eps")


  call vca_init_solver(comm)

  !htb=Htb_square_lattice(2,2,1.d0)
  !t_prime=vca_lso2nnn_reshape(htb,Nlat,Nspin,Norb)
  call generate_tcluster()
  call generate_hk()
  call vca_solve(comm,t_prime,h_k)
  !call print_2DLattice_Structure(dcmplx(htb),[Nx,Ny],1,1,file="Htb_vecchio")
  !call print_2DLattice_Structure(vca_nnn2lso_reshape(t_prime,Nlat,Nspin,Norb),[Nx,Ny],1,1,file="Htb_nuovo")

  if(wloop)then
    allocate(ts_array(Nloop))
    allocate(omega_array(Nloop))
    ts_array = linspace(1.d-2,5.d0,Nloop)
    !
    do iloop=1,Nloop
       omega_array(iloop)=solve_vca_square(ts_array(iloop))
    enddo
    !
    call splot("sft_Omega_loopVSts.dat",ts_array,omega_array)
    min_loc = minloc(omega_array)
    write(800,*)min_loc,ts_array(min_loc(1)),omega_array(min_loc(1))
  endif

  !MINIMIZATION:

  if(wmin)then
     print*,"Guess:",ts
     call  brent(solve_vca_square,ts,[0.5d0,3d0])
     print*,"Result ts : ",ts
     t_var=ts
  endif

  allocate(gtest_real(Nspin,Nspin,Norb,Norb,Lmats))
  allocate(sigmatest_real(Nspin,Nspin,Norb,Norb,Lmats))
  allocate(gtest_mats(Nspin,Nspin,Norb,Norb,Lmats))
  allocate(sigmatest_mats(Nspin,Nspin,Norb,Norb,Lmats))
  gtest_mats=zero
  sigmatest_mats=zero
  gtest_real=zero
  sigmatest_real=zero
  !
  allocate(kgrid_test(Nkpts**ndim,Ndim)) 
  call TB_build_kgrid([Nkpts,Nkpts],kgrid_test)
  do ik=1,Nkpts**ndim
      !print*,ik
      !call periodize_g_scheme([(2*pi/Nkpts)*ik])
      call build_sigma_g_scheme([0d0,0d0])  !also periodizes g
      do ix=1,Lmats
          gtest_mats(:,:,:,:,ix)=gtest_mats(:,:,:,:,ix)+gfmats_periodized(:,:,:,:,ix)/(Nkpts**Ndim)
          sigmatest_mats(:,:,:,:,ix)=sigmatest_mats(:,:,:,:,ix)+impSmats_periodized(:,:,:,:,ix)/(Nkpts**Ndim)
      enddo
      do ix=1,Lreal
          gtest_real(:,:,:,:,ix)=gtest_real(:,:,:,:,ix)+gfreal_periodized(:,:,:,:,ix)/(Nkpts**Ndim)
          sigmatest_real(:,:,:,:,ix)=sigmatest_real(:,:,:,:,ix)+impSreal_periodized(:,:,:,:,ix)/(Nkpts**Ndim)
      enddo
  enddo
  gfmats_periodized=gtest_mats
  impSmats_periodized=sigmatest_mats
  gfreal_periodized=gtest_real
  impSreal_periodized=sigmatest_real
  call print_periodized()


  call finalize_MPI()





contains

  !+------------------------------------------------------------------+
  !PURPOSE  : solve the model
  !+------------------------------------------------------------------+



  function solve_vca_square(tij) result(Omega)
    real(8)                      :: tij
    real(8)                      :: Omega
    !
    !
    t_var=tij
    print*,""
    print*,"------ t = ",t_var,"------"
    call generate_tcluster()
    call generate_hk()
    call vca_solve(comm,t_prime,h_k)
    call vca_get_sft_potential(omega)
    print*,""
    print*,"------ DONE ------"
    print*,""
    !
  end function solve_vca_square


  !+------------------------------------------------------------------+
  !PURPOSE  : generate test hopping matrices
  !+------------------------------------------------------------------+

  subroutine generate_tcluster()
    integer                                      :: ilat,jlat,ispin,iorb,ind1,ind2
    real(8),dimension(Nlso,Nlso)                 :: H0
    character(len=64)                            :: file_
    integer                                      :: unit
    file_ = "tcluster_matrix.dat"
    !
    if(allocated(t_prime))deallocate(t_prime)
    allocate(t_prime(Nlat,Nlat,Nspin,Nspin,Norb,Norb))
    t_prime=zero
    !
    do ispin=1,Nspin
      do ilat=1,Nx
        do jlat=1,Nx
          ind1=indices2N([ilat,jlat])
          t_prime(ind1,ind1,ispin,ispin,1,1)= -mu_var
          if(ilat<Nx)then
            ind2=indices2N([ilat+1,jlat])
            t_prime(ind1,ind2,ispin,ispin,1,1)= -t_var
          endif
          if(ilat>1)then
            ind2=indices2N([ilat-1,jlat])
            t_prime(ind1,ind2,ispin,ispin,1,1)= -t_var
          endif
          if(jlat<Nx)then
            ind2=indices2N([ilat,jlat+1])
            t_prime(ind1,ind2,ispin,ispin,1,1)= -t_var

          endif
          if(jlat>1)then
            ind2=indices2N([ilat,jlat-1])
            t_prime(ind1,ind2,ispin,ispin,1,1)= -t_var
          endif
        enddo
      enddo
    enddo
    !
    H0=vca_nnn2lso_reshape(t_prime,Nlat,Nspin,Norb)
    !
    open(free_unit(unit),file=trim(file_))
    do ilat=1,Nlat*Nspin*Norb
       write(unit,"(5000(F5.2,1x))")(H0(ilat,jlat),jlat=1,Nlat*Nspin*Norb)
    enddo
    close(unit)
  end subroutine generate_tcluster




  subroutine generate_hk()
    integer                                      :: ik,ii,ispin,iorb,unit,jj
    real(8),dimension(Nkpts**Ndim,Ndim)          :: kgrid
    real(8),dimension(Nlso,Nlso)                 :: H0
    character(len=64)                            :: file_
    file_ = "tlattice_matrix.dat"
    !
    call TB_build_kgrid([Nkpts,Nkpts],kgrid)
    kgrid=kgrid/Nx !!!!!DIVIDI OGNI K PER NUMERO SITI in quella direzione, RBZ
    if(allocated(h_k))deallocate(h_k)
    allocate(h_k(Nlat,Nlat,Nspin,Nspin,Norb,Norb,Nkpts**ndim)) 
    h_k=zero
    !
    do ik=1,Nkpts**ndim
        !
        h_k(:,:,:,:,:,:,ik)=tk(kgrid(ik,:))
        !
    enddo
    H0=vca_nnn2lso_reshape(tk([0.3d0,0.6d0]),Nlat,Nspin,Norb)
    !
    open(free_unit(unit),file=trim(file_))
    do ilat=1,Nlat*Nspin*Norb
       write(unit,"(5000(F5.2,1x))")(H0(ilat,jlat),jlat=1,Nlat*Nspin*Norb)
    enddo
    close(unit)    
  end subroutine generate_hk


  function tk(kpoint) result(hopping_matrix)
    integer                                                                 :: ilat,jlat,ispin,iorb,i,j,ind1,ind2
    real(8),dimension(Ndim),intent(in)                                      :: kpoint
    complex(8),dimension(Nlat,Nlat,Nspin,Nspin,Norb,Norb)                   :: hopping_matrix
    !
    hopping_matrix=zero
    !
    do ilat=1,Nx
      do jlat=1,Ny
        do ispin=1,Nspin
          ind1=indices2N([ilat,jlat])
          hopping_matrix(ind1,ind1,ispin,ispin,1,1)= -mu
          if(ilat<Nx)then
            ind2=indices2N([ilat+1,jlat])
            hopping_matrix(ind1,ind2,ispin,ispin,1,1)= -t
          endif
          if(ilat>1)then
            ind2=indices2N([ilat-1,jlat])
            hopping_matrix(ind1,ind2,ispin,ispin,1,1)= -t
          endif
          if(jlat<Ny)then
            ind2=indices2N([ilat,jlat+1])
            hopping_matrix(ind1,ind2,ispin,ispin,1,1)= -t
          endif
          if(jlat>1)then
            ind2=indices2N([ilat,jlat-1])
            hopping_matrix(ind1,ind2,ispin,ispin,1,1)= -t
          endif
        enddo
      enddo
    enddo
    !
    do ilat=1,Nx
      do ispin=1,Nspin
        ind1=indices2N([1,ilat])
        ind2=indices2N([Nx,ilat])
        hopping_matrix(ind1,ind2,ispin,ispin,1,1)=hopping_matrix(ind1,ind2,ispin,ispin,1,1) -t*exp(xi*kpoint(2)*Nx)
        hopping_matrix(ind2,ind1,ispin,ispin,1,1)=hopping_matrix(ind2,ind1,ispin,ispin,1,1) -t*exp(-xi*kpoint(2)*Nx)
        !
        ind1=indices2N([ilat,1])
        ind2=indices2N([ilat,Ny])
        hopping_matrix(ind1,ind2,ispin,ispin,1,1)=hopping_matrix(ind1,ind2,ispin,ispin,1,1) -t*exp(xi*kpoint(1)*Ny)
        hopping_matrix(ind2,ind1,ispin,ispin,1,1)=hopping_matrix(ind2,ind1,ispin,ispin,1,1) -t*exp(-xi*kpoint(1)*Ny)
      enddo
    enddo
    ! 
  end function tk

  !+------------------------------------------------------------------+
  !Periodization functions
  !+------------------------------------------------------------------+

 subroutine periodize_g_scheme(kpoint)
    integer                                                     :: ilat,jlat,ispin,iorb,ii
    real(8),dimension(Ndim)                                     :: kpoint,ind1,ind2
    complex(8),allocatable,dimension(:,:,:,:,:,:)               :: gfprime ![Nlat][Nlat][Nspin][Nspin][Norb][Norb]
    complex(8),allocatable,dimension(:,:,:,:,:,:,:)             :: gfreal_unperiodized![Nlat][Nlat][Nspin][Nspin][Norb][Norb][Lmats]
    complex(8),allocatable,dimension(:,:,:,:,:,:,:)             :: gfmats_unperiodized ![Nlat][Nlat][Nspin][Nspin][Norb][Norb][Lreal]
    !
    if(.not.allocated(wm))allocate(wm(Lmats))
    if(.not.allocated(wr))allocate(wr(Lreal))
    wm     = pi/beta*real(2*arange(1,Lmats)-1,8)
    wr     = linspace(wini,wfin,Lreal)
    !
    allocate(gfmats_unperiodized(Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lmats))
    allocate(gfreal_unperiodized(Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lreal))
    allocate(gfprime(Nlat,Nlat,Nspin,Nspin,Norb,Norb))
    if(.not.allocated(gfmats_periodized))allocate(gfmats_periodized(Nspin,Nspin,Norb,Norb,Lmats))
    if(.not.allocated(gfreal_periodized))allocate(gfreal_periodized(Nspin,Nspin,Norb,Norb,Lreal))
    !
    gfmats_unperiodized=zero
    gfreal_unperiodized=zero
    gfprime=zero
    gfmats_periodized=zero
    gfreal_periodized=zero
    !
    !
    do ii=1,Lmats    
        call vca_gf_cluster(xi*wm(ii),gfprime)
        gfmats_unperiodized(:,:,:,:,:,:,ii)=gfprime+t_prime-tk(kpoint)
    enddo
    !
    do ii=1,Lreal    
        call vca_gf_cluster(dcmplx(wr(ii),eps),gfprime)
        gfreal_unperiodized(:,:,:,:,:,:,ii)=gfprime+t_prime-tk(kpoint)
    enddo
    !
    do ii=1,Lmats
        do ilat=1,Nlat
          ind1=N2indices(ilat)        
          do jlat=1,Nlat
            ind2=N2indices(jlat)
            do ispin=1,Nspin
               gfmats_periodized(:,:,:,:,ii)=gfmats_periodized(:,:,:,:,ii)+exp(-xi*dot_product(kpoint,ind2-ind1))*gfmats_unperiodized(ilat,jlat,:,:,:,:,ii)/Nlat
            enddo
          enddo
        enddo
    enddo
    !
    do ii=1,Lreal   
     do ilat=1,Nlat
        do jlat=1,Nlat
          gfreal_periodized(:,:,:,:,ii)=gfreal_periodized(:,:,:,:,ii)+exp(-xi*dot_product(kpoint,ind2-ind1))*gfreal_unperiodized(ilat,jlat,:,:,:,:,ii)/Nlat
        enddo
      enddo
    enddo
    !
    if(allocated(wm))deallocate(wm)
    if(allocated(wr))deallocate(wr) 
    !   
  end subroutine periodize_g_scheme



  subroutine build_sigma_g_scheme(kpoint)
    integer                                                     :: i,ispin,iorb,ii
    real(8),dimension(Ndim)                                     :: kpoint
    complex(8),dimension(Nspin,Nspin,Norb,Norb,Lmats)           :: invG0mats,invGmats
    complex(8),dimension(Nspin,Nspin,Norb,Norb,Lreal)           :: invG0real,invGreal
    !
    if(.not.allocated(wm))allocate(wm(Lmats))
    if(.not.allocated(wr))allocate(wr(Lreal))
    wm     = pi/beta*real(2*arange(1,Lmats)-1,8)
    wr     = linspace(wini,wfin,Lreal)
    !
    if(.not.allocated(impSmats_periodized))allocate(impSmats_periodized(Nspin,Nspin,Norb,Norb,Lmats))
    if(.not.allocated(impSreal_periodized))allocate(impSreal_periodized(Nspin,Nspin,Norb,Norb,Lreal))
    invG0mats = zero
    invGmats  = zero
    invG0real = zero
    invGreal  = zero
    impSmats_periodized  = zero
    impSreal_periodized  = zero
    !
    !Get G0^-1
    !invG0mats = invg0_bath_mats(dcmplx(0d0,wm(:)),vca_bath)
    !invG0real = invg0_bath_real(dcmplx(wr(:),eps),vca_bath)
    !
    !Get G0^-1
    do ispin=1,Nspin
      do iorb=1,Norb
        do ii=1,Lmats
            invG0mats(ispin,ispin,iorb,iorb,ii) = (xi*wm(ii)+xmu)  + 2.d0*t_var*(cos(kpoint(1)) + cos(kpoint(2)))             ! FIXME: ad-hoc solution
        enddo
        do ii=1,Lreal
            invG0real(ispin,ispin,iorb,iorb,ii) = (wr(ii)+xmu)   + 2.d0*t_var*(cos(kpoint(1)) + cos(kpoint(2)))               ! FIXME: ad-hoc solution
        enddo
      enddo
    enddo
    !
    !Get Gimp^-1
    call periodize_g_scheme(kpoint)
    do ispin=1,Nspin
      do iorb=1,Norb
         invGmats(ispin,ispin,iorb,iorb,:) = one/gfmats_periodized(ispin,ispin,iorb,iorb,:)
         invGreal(ispin,ispin,iorb,iorb,:) = one/gfreal_periodized(ispin,ispin,iorb,iorb,:)
      enddo
    enddo
    !Get Sigma functions: Sigma= G0^-1 - G^-1
    impSmats_periodized=zero
    impSreal_periodized=zero
    do ispin=1,Nspin
      do iorb=1,Norb
         impSmats_periodized(ispin,ispin,iorb,iorb,:) = invG0mats(ispin,ispin,iorb,iorb,:) - invGmats(ispin,ispin,iorb,iorb,:)
         impSreal_periodized(ispin,ispin,iorb,iorb,:) = invG0real(ispin,ispin,iorb,iorb,:) - invGreal(ispin,ispin,iorb,iorb,:)
      enddo
    enddo
    !
    !
    if(allocated(wm))deallocate(wm)
    if(allocated(wr))deallocate(wr)
    !
  end subroutine build_sigma_g_scheme



  subroutine print_periodized()
    character(len=64) :: suffix
    integer           :: iorb,ispin
    !
    if(.not.allocated(wm))allocate(wm(Lmats))
    if(.not.allocated(wr))allocate(wr(Lreal))
    wm     = pi/beta*real(2*arange(1,Lmats)-1,8)
    wr     = linspace(wini,wfin,Lreal)
    !
    do iorb=1,Norb
     do ispin=1,Nspin
        suffix="_l"//str(iorb)//str(iorb)//"_s"//str(ispin)
        call splot("perG"//reg(suffix)//"_iw.vca"   ,wm,gfmats_periodized(ispin,ispin,iorb,iorb,:))
        call splot("perG"//reg(suffix)//"_realw.vca",wr,gfreal_periodized(ispin,ispin,iorb,iorb,:))
        call splot("perSigma"//reg(suffix)//"_iw.vca"   ,wm,impSmats_periodized(ispin,ispin,iorb,iorb,:))
        call splot("perSigma"//reg(suffix)//"_realw.vca",wr,impSreal_periodized(ispin,ispin,iorb,iorb,:))
      enddo
    enddo
    !
    if(allocated(wm))deallocate(wm)
    if(allocated(wr))deallocate(wr)
    !
  end subroutine print_periodized

 


  !+------------------------------------------------------------------+
  !Auxilliary functions
  !+------------------------------------------------------------------+

  function indices2N(indices) result(N)
    integer,dimension(Ndim)      :: indices
    integer                      :: N,i
    !
    !
    N=1
    do i=1,Ndim
      N=N+((Nx)**(i-1))*(indices(i)-1)
    enddo
  end function indices2N

  function N2indices(N_) result(indices) ! FIXME: only for 2d
    integer,dimension(Ndim)      :: indices
    integer                      :: N,i,N_
    !
    N=N_-1
    indices(1)=mod(N,Nx)+1
    indices(2)=N/Nx+1
  end function N2indices


end program vca_test



