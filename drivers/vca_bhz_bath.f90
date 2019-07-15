program vca_bhz_2d
  USE SCIFOR
  USE DMFT_TOOLS
  USE MPI
  USE VCA
  !
  !System parameters
  implicit none
  integer                                         :: Nlso
  integer                                         :: Nx,Ny,Ndim
  integer,dimension(2)                            :: Nkpts
  integer                                         :: ilat,jlat
  real(8)                                         :: ts,ts_var,Mh,Mh_var,lambdauser,lambdauser_var
  real(8)                                         :: M,M_var,t,t_var,lambda,lambda_var,mu,mu_var
  real(8)                                         :: bath_e,bath_v
  !Bath
  integer                                         :: Nb
  real(8),allocatable                             :: Bath(:)
  !Matrices:
  real(8),allocatable,dimension(:)                :: wm,wr
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: t_prime
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: observable_matrix
  complex(8),allocatable,dimension(:,:,:,:,:,:,:) :: h_k
  complex(8),allocatable,dimension(:,:,:,:,:)     :: gfmats_local,gfmats_periodized     ![Nspin][Nspin][Norb][Norb][L]
  complex(8),allocatable,dimension(:,:,:,:,:)     :: gfreal_local,gfreal_periodized     ![Nspin][Nspin][Norb][Norb][L]
  complex(8),allocatable,dimension(:,:,:,:,:)     :: Smats_local,Smats_periodized       ![Nspin][Nspin][Norb][Norb][L]
  complex(8),allocatable,dimension(:,:,:,:,:)     :: Sreal_local,Sreal_periodized       ![Nspin][Nspin][Norb][Norb][L]
  complex(8),allocatable,dimension(:,:,:)         :: Smats_periodized_lso,Sreal_periodized_lso    
  !Utility variables:
  integer                                         :: unit
  integer                                         :: comm,rank
  integer                                         :: iloop,jloop,nloop
  integer                                         :: iii,jjj,kkk
  logical                                         :: master,wloop,wmin,MULTIMAX
  logical                                         :: usez
  logical                                         :: print_mats,print_real
  character(len=6)                                :: scheme
  character(len=16)                               :: finput
  real(8)                                         :: omegadummy,observable_dummy
  real(8),dimension(:),allocatable                :: ts_array_x,ts_array_y,params
  real(8),dimension(:,:),allocatable              :: omega_grid
  real(8),allocatable,dimension(:,:)              :: kgrid_test,kpath_test
  real(8),dimension(3)                            :: df
  !
  !MPI INIT
  !
  call init_MPI()
  comm = MPI_COMM_WORLD
  call StartMsg_MPI(comm)
  rank = get_Rank_MPI(comm)
  master = get_Master_MPI(comm)
  !
  !PARSE INPUT VARIABLES
  !
  call parse_cmd_variable(finput,"FINPUT",default='inputVCA.conf')
  call parse_input_variable(ts,"ts",finput,default=0.5d0,comment="Hopping parameter (units of epsilon)")
  call parse_input_variable(Nkpts,"Nkpts",finput,default=[10,10],comment="Number of k-points along each direction")
  call parse_input_variable(Mh,"Mh",finput,default=3d0,comment="Field splitting (units of epsilon)")
  call parse_input_variable(lambdauser,"lambda",finput,default=0.3d0,comment="Spin/orbit coupling (units of epsilon)")
  call parse_input_variable(ts_var,"ts_Var",finput,default=0.5d0,comment="variational hopping parameter (units of epsilon)")
  call parse_input_variable(Mh_var,"Mh_Var",finput,default=3d0,comment="variational field splitting (units of epsilon)")
  call parse_input_variable(lambdauser_var,"lambda_var",finput,default=0.3d0,comment="variational spin/orbit coupling (units of epsilon)")
  call parse_input_variable(Nx,"Nx",finput,default=2,comment="Number of sites along X")
  call parse_input_variable(Ny,"Ny",finput,default=2,comment="Number of sites along Y")
  call parse_input_variable(nloop,"NLOOP",finput,default=100)
  call parse_input_variable(wloop,"WLOOP",finput,default=.false.)
  call parse_input_variable(wmin,"WMIN",finput,default=.false.,comment="T: includes global minimization")
  call parse_input_variable(scheme,"SCHEME",finput,default="g")
  call parse_input_variable(print_mats,"PRINT_MATS",finput,default=.true.)
  call parse_input_variable(print_real,"PRINT_REAL",finput,default=.true.)
  call parse_input_variable(scheme,"SCHEME",finput,default="g")
  call parse_input_variable(usez,"USEZ",finput,default=.false.)
  !
  call vca_read_input(trim(finput),comm)
  !
  !
  !Add DMFT CTRL Variables:
  call add_ctrl_var(Nlat,"NLAT")
  call add_ctrl_var(Norb,"norb")
  call add_ctrl_var(Nspin,"nspin")
  call add_ctrl_var(beta,"beta")
  call add_ctrl_var(xmu,"xmu")
  call add_ctrl_var(wini,'wini')
  call add_ctrl_var(wfin,'wfin')
  call add_ctrl_var(eps,"eps")
  !
  !
  !SET CLUSTER DIMENSIONS (ASSUME SQUARE CLUSTER):
  !
  Ndim=size(Nkpts)
  Nlat=Nx*Ny
  Nlso = Nlat*Norb*Nspin
  !
  !SET BATH
  !
  Nb=vca_get_bath_dimension()
  allocate(Bath(Nb))
  !
  !SET LATTICE PARAMETERS (GLOBAL VARIABLES FOR THE DRIVER):
  !
  t=ts
  M=(2.d0*t)*Mh
  lambda=(2.d0*t)*lambdauser
  mu=0.d0*t
  !
  !ALLOCATE VECTORS:
  !
  if(.not.allocated(wm))allocate(wm(Lmats))
  if(.not.allocated(wr))allocate(wr(Lreal))
  if(.not.allocated(params))allocate(params(3))
  wm     = pi/beta*real(2*arange(1,Lmats)-1,8)
  wr     = linspace(wini,wfin,Lreal)
  !
  !INITIALIZE SOLVER:
  !
  call vca_init_solver(comm,bath)
  print_impG=.false.
  print_impG0=.false.
  print_Sigma=.false.
  print_observables=.false.
  MULTIMAX=.false.
  !
  !SOLVE INTERACTING PROBLEM:
  ! 
  if(wmin)then
    !
    !
    bath_v=0.5
    print*,"Guess:",bath_v
    call  brent(solve_vca_single,bath_v,[0.01d0,1d0])
    print*,"Result ts : ",bath_v
    print_impG=.true.
    print_impG0=.true.
    print_Sigma=.true.
    print_observables=.true.
    omegadummy=solve_vca_single(bath_v)
    !INITIALIZE VARIABLES TO THE LATTICE VALUES
    !
    !params=[t,M,lambda]
    !
    !call minimize_parameters(params,0.5d0)
    !call fmin_brent(params,0.2d0)
    !
    !print_Sigma=.true.
    !print_observables=.true.
    !omegadummy=solve_vca_multi(params)
    !
    !write(*,"(A,F15.9,A,3F15.9)")bold_green("FOUND STATIONARY POINT "),omegadummy,bold_green(" AT "),t_var,m_var,lambda_var
    !write(*,"(A)")""
    !
    !call solve_Htop_new()
    !
  elseif(wloop)then
    !
    allocate(ts_array_x(Nloop))
    allocate(omega_grid(Nloop,Nloop))
    !
    ts_array_x = linspace(0.01d0,1d0,Nloop)
    do iloop=1,Nloop
        omega_grid(iloop,1)=solve_vca_multi([ts_var,Mh_var,lambda,0.d0,ts_array_x(iloop)])
    enddo
    !
    call splot("sft_Omega_loopVSts.dat",ts_array_x,omega_grid(:,1))
    !
    !allocate(ts_array_x(Nloop))
    !allocate(ts_array_y(Nloop))
    !allocate(omega_grid(Nloop,Nloop))
    !
    !ts_array_x = linspace(0.1d0,0.15d0,Nloop)
    !ts_array_y = linspace(0.01d0,1.0d0,Nloop)
    !
    !do iloop=1,Nloop
    !  do jloop=1,Nloop
    !    omega_grid(iloop,jloop)=solve_vca_multi([ts_var,Mh_var,lambda,ts_array_x(iloop),ts_array_y(jloop)])
    !  enddo
    !enddo
    !
    !call splot3d("sft_Omega_loopVSts.dat",ts_array_x,ts_array_y,omega_grid)
  else
    print_observables=.true.
    !omegadummy=solve_vca_multi([ts_var,Mh_Var,lambdauser_var])
    !print*,"calculate gradient"
    !call fdjac_1n_func(solve_vca_multi,[ts_var,Mh_Var,lambdauser_var],df)
    !print*,"gradient is", df
    !
    !write(*,"(A,F15.9,A,3F15.9)")bold_green("OMEGA IS "),omegadummy,bold_green(" AT "),ts_var,Mh_Var,lambdauser_var
    !
    !allocate(observable_matrix(Nlat,Nlat,Nspin,Nspin,Norb,Norb))
    !
    !SET OBSERVABLE MATRIX: AS AN EXAMPLE, THE TWO ORBITAL OCCUPATIONS
    !
    !observable_matrix=zero
    !do iii=1,Nlat
    !      observable_matrix(iii,iii,1,1,1,1)=1.d0
    !      observable_matrix(iii,iii,2,2,1,1)=1.d0
    !enddo
    !call observables_lattice(observable_matrix,observable_dummy)
    !print*,"User-requested observable with value store is ",observable_dummy
    !
    !observable_matrix=zero
    !do iii=1,Nlat
    !      observable_matrix(iii,iii,1,1,2,2)=1.d0
    !      observable_matrix(iii,iii,2,2,2,2)=1.d0
    !enddo
    !call observables_lattice(observable_matrix)
  endif
  !
  !PRINT LOCAL GF AND SIGMA
  !
  call solve_Htop_new()
  !
  if(allocated(wm))deallocate(wm)
  if(allocated(wr))deallocate(wr)
  if(allocated(params))deallocate(params)
  !
  call finalize_MPI()
  !
contains

  !+------------------------------------------------------------------+
  !PURPOSE  : solve the model
  !+------------------------------------------------------------------+


  function solve_vca_single(x) result(Omega_)
    real(8)                   :: x,Omega_
    !
    Omega_=solve_vca_multi([t,M,lambda,0.d0,x])
    !
  end function solve_vca_single

  function solve_vca_multi(pars) result(Omega)
    integer                      :: ix,iy,ik,iq,iz
    real(8)                      :: Vij,Eij,deltae
    real(8),dimension(:)         :: pars
    real(8),dimension(Nbath)     :: evector,vvector,tmp
    logical                      :: invert
    real(8)                      :: Omega
    !
    !SET VARIATIONAL PARAMETERS (GLOBAL VARIABLES FOR THE DRIVER):
    !
    t_var=pars(1)  
    M_var=pars(2)
    lambda_var=pars(3)
    deltae=pars(4)
    Vij=pars(5)
    !
    mu_var=0.d0*t_var
    Eij=0.d0
    !
    if(NBATH>1)then
      tmp=linspace(0.d0,deltae,Nbath)
    else
      tmp=0.5d0*deltae
    endif
    !
    do iy=1,Nbath
      evector(iy)=Eij+tmp(iy)-0.5d0*deltae
      vvector(iy)=Vij
    enddo
    do ix=1,Nx
      do iq=1,Ny
        iz=indices2N([ix,iq])
        do iy=1,Nspin
          do ik=1,Norb
            call set_bath_component(bath,iz,iy,ik,e_component=evector)
            call set_bath_component(bath,iz,iy,ik,v_component=vvector)
          enddo
        enddo
      enddo
    enddo

    !
    print*,""
    print*,"Variational parameters:"
    print*,"t      = ",t_var
    print*,"M      = ",m_var
    print*,"lambda = ",lambda_var
    print*,"Lattice parameters:"
    print*,"t      = ",t
    print*,"M      = ",m
    print*,"lambda = ",lambda
    call generate_tcluster()
    call generate_hk()
    call vca_solve(comm,t_prime,h_k,bath)
    call vca_get_sft_potential(omega)
    !
    if(MULTIMAX)omega=-omega
    !    
    print*,""
    !
  end function solve_vca_multi


  !+------------------------------------------------------------------+
  !PURPOSE  : generate hopping matrices (assume Ny=1)
  !+------------------------------------------------------------------+


  subroutine generate_tcluster()
    integer                                      :: ilat,jlat,ispin,iorb,jorb,ind1,ind2
    complex(8),dimension(Nlso,Nlso)              :: H0
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
        do jlat=1,Ny
          ind1=indices2N([ilat,jlat])
          t_prime(ind1,ind1,ispin,ispin,:,:)= t_m(m_var)
          if(ilat<Nx)then
            ind2=indices2N([ilat+1,jlat])
            t_prime(ind1,ind2,ispin,ispin,:,:)= t_x(t_var,lambda_var,ispin)
          endif
          if(ilat>1)then
            ind2=indices2N([ilat-1,jlat])
            t_prime(ind1,ind2,ispin,ispin,:,:)= dconjg(transpose(t_x(t_var,lambda_var,ispin)))
          endif
          if(jlat<Ny)then
            ind2=indices2N([ilat,jlat+1])
            t_prime(ind1,ind2,ispin,ispin,:,:)= t_y(t_var,lambda_var)
          endif
          if(jlat>1)then
            ind2=indices2N([ilat,jlat-1])
            t_prime(ind1,ind2,ispin,ispin,:,:)= transpose(t_y(t_var,lambda_var))
          endif
        enddo
      enddo
    enddo
    !
    H0=vca_nnn2lso_reshape(t_prime,Nlat,Nspin,Norb)
    !
    open(free_unit(unit),file=trim(file_))
    do ilat=1,Nlat*Nspin*Norb
       write(unit,"(5000(F5.2,1x))")(REAL(H0(ilat,jlat)),jlat=1,Nlat*Nspin*Norb)
    enddo
    write(unit,*)"                  "
    do ilat=1,Nlat*Nspin*Norb
       write(unit,"(5000(F5.2,1x))")(IMAG(H0(ilat,jlat)),jlat=1,Nlat*Nspin*Norb)
    enddo
    close(unit)
  end subroutine generate_tcluster


 function tk(kpoint) result(hopping_matrix)
    integer                                                                 :: ilat,jlat,ispin,iorb,jorb,i,j,ind1,ind2
    real(8),dimension(Ndim),intent(in)                                      :: kpoint
    complex(8),dimension(Nlat,Nlat,Nspin,Nspin,Norb,Norb)                   :: hopping_matrix
    !
    hopping_matrix=zero
    !
    do ispin=1,Nspin
      do ilat=1,Nx
        do jlat=1,Ny
          ind1=indices2N([ilat,jlat])
          hopping_matrix(ind1,ind1,ispin,ispin,:,:)= t_m(m)
          if(ilat<Nx)then
            ind2=indices2N([ilat+1,jlat])
            hopping_matrix(ind1,ind2,ispin,ispin,:,:)= t_x(t,lambda,ispin)
          endif
          if(ilat>1)then
            ind2=indices2N([ilat-1,jlat])
            hopping_matrix(ind1,ind2,ispin,ispin,:,:)= dconjg(transpose(t_x(t,lambda,ispin)))
          endif
          if(jlat<Ny)then
            ind2=indices2N([ilat,jlat+1])
            hopping_matrix(ind1,ind2,ispin,ispin,:,:)= t_y(t,lambda)
          endif
          if(jlat>1)then
            ind2=indices2N([ilat,jlat-1])
            hopping_matrix(ind1,ind2,ispin,ispin,:,:)= transpose(t_y(t,lambda))
          endif
        enddo
      enddo
    enddo
    !
    !
    do ispin=1,Nspin
      do ilat=1,Ny
        ind1=indices2N([1,ilat])
        ind2=indices2N([Nx,ilat])
        hopping_matrix(ind1,ind2,ispin,ispin,:,:)=hopping_matrix(ind1,ind2,ispin,ispin,:,:) + dconjg(transpose(t_x(t,lambda,ispin)))*exp(xi*kpoint(1)*Nx)
        hopping_matrix(ind2,ind1,ispin,ispin,:,:)=hopping_matrix(ind2,ind1,ispin,ispin,:,:) + t_x(t,lambda,ispin)*exp(-xi*kpoint(1)*Nx)
      enddo
      do ilat =1,Nx
        ind1=indices2N([ilat,1])
        ind2=indices2N([ilat,Ny])
        hopping_matrix(ind1,ind2,ispin,ispin,:,:)=hopping_matrix(ind1,ind2,ispin,ispin,:,:) + transpose(t_y(t,lambda))*exp(xi*kpoint(2)*Ny)
        hopping_matrix(ind2,ind1,ispin,ispin,:,:)=hopping_matrix(ind2,ind1,ispin,ispin,:,:) + t_y(t,lambda)*exp(-xi*kpoint(2)*Ny)
      enddo
    enddo
    !
    ! 
  end function tk

  subroutine generate_hk()
    integer                                      :: ik,ii,ispin,iorb,unit,jj
    real(8),dimension(product(Nkpts),Ndim)          :: kgrid
    real(8),dimension(Nlso,Nlso)                 :: H0
    character(len=64)                            :: file_
    file_ = "tlattice_matrix.dat"
    !
    call TB_build_kgrid(Nkpts,kgrid)
    !Reduced Brillouin Zone
    kgrid=kgrid/Nx 
    !
    if(allocated(h_k))deallocate(h_k)
    allocate(h_k(Nlat,Nlat,Nspin,Nspin,Norb,Norb,product(Nkpts))) 
    h_k=zero
    !
    do ik=1,product(Nkpts)
        !
        h_k(:,:,:,:,:,:,ik)=tk(kgrid(ik,:))
        !
    enddo
    H0=vca_nnn2lso_reshape(tk([0.d0,0.d0]),Nlat,Nspin,Norb)
    !
    open(free_unit(unit),file=trim(file_))
    do ilat=1,Nlat*Nspin*Norb
       write(unit,"(5000(F5.2,1x))")(H0(ilat,jlat),jlat=1,Nlat*Nspin*Norb)
    enddo
    close(unit)    
  end subroutine generate_hk


!AUXILLIARY HOPPING MATRIX CONSTRUCTORS

  function t_m(mass) result(tmpmat)
    complex(8),dimension(Norb,Norb) :: tmpmat
    real(8)                         :: mass
    !
    tmpmat=zero
    tmpmat=mass*pauli_sigma_z
    !
  end function t_m

  function t_x(hop1,hop2,spinsign) result(tmpmat)
    complex(8),dimension(Norb,Norb) :: tmpmat
    real(8)                         :: hop1,hop2,sz
    integer                         :: spinsign
    !
    tmpmat=zero
    sz=(-1.d0)**(spinsign+1)
    tmpmat=-hop1*pauli_sigma_z+0.5d0*sz*xi*hop2*pauli_sigma_x
    !
  end function t_x

  function t_y(hop1,hop2) result(tmpmat)
    complex(8),dimension(Norb,Norb) :: tmpmat
    real(8)                         :: hop1,hop2
    !
    tmpmat=zero
    tmpmat=-hop1*pauli_sigma_z
    tmpmat(1,2)=-hop2*0.5d0
    tmpmat(2,1)=hop2*0.5d0
    !
  end function t_y


  !+------------------------------------------------------------------+
  !PURPOSE  : PRINT HAMILTONIAN ALONG PATH
  !+------------------------------------------------------------------+

  function hk_bhz_clusterbase(kpoint,N) result(hopping_matrix_lso)
    integer                                                       :: N,ilat,jlat
    real(8),dimension(:)                                          :: kpoint
    real(8),dimension(Ndim)                                       :: kpoint_
    complex(8),dimension(N,N)                                     :: hopping_matrix_lso
    complex(8),dimension(Nlat,Nlat,Nspin,Nspin,Norb,Norb)         :: hopping_matrix_big
    complex(8),dimension(Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lmats)   :: tmpSigmaMat
    real(8)                                                       :: energy_scale
    if(N.ne.Nlat*Nspin*Norb)stop "error N: wrong dimension"
    !
    hopping_matrix_lso=zero
    hopping_matrix_big=zero
    !
    !
    call vca_get_sigma_matsubara(tmpSigmaMat)
    hopping_matrix_big=tk(kpoint)+DREAL(TmpSigmaMat(:,:,:,:,:,:,1))
    !
    !
    hopping_matrix_lso=vca_nnn2lso_reshape(Hopping_matrix_big,Nlat,Nspin,Norb)
    !
  end function hk_bhz_clusterbase



  subroutine solve_Htop_new(kpath_)
    integer                                  :: i,j
    integer                                  :: Npts,Nkpath
    type(rgb_color),dimension(:),allocatable :: colors
    real(8),dimension(:,:),optional          :: kpath_
    real(8),dimension(:,:),allocatable       :: kpath
    character(len=64)                        :: file
    !
    Nkpath=100
    !
    if(present(kpath_))then
       if(master)write(LOGfile,*)"Build H(k) BHZ along a given path:"
       Npts = size(kpath_,1)
       allocate(kpath(Npts,size(kpath_,2)))
       kpath=kpath_
    else
       if(master)write(LOGfile,*)"Build H(k) BHZ along the path GXMG:"
       Npts = 4
       allocate(kpath(Npts,2))
       kpath(1,:)=[0.d0,0.d0]
       kpath(2,:)=[pi/Nx,pi/Nx]
       kpath(3,:)=[pi/Nx,0.d0]
       kpath(4,:)=[0.d0,0.d0]
    endif
    allocate(colors(Nlat*Nspin*Norb))
    colors = gray99
    !
    do i=0,Nlat-1
      colors(1+i*Nspin*Norb) = red1
      colors(2+i*Nspin*Norb) = blue1
      colors(3+i*Nspin*Norb) = red1
      colors(4+i*Nspin*Norb) = blue1
    enddo
   !
   file="Eig_Htop_clusterbase.nint"
   if(master) call TB_Solve_model(hk_bhz_clusterbase,Nlat*Nspin*Norb,kpath,Nkpath,&   
         colors_name=colors,&
         points_name=[character(len=20) :: 'G', 'M', 'X', 'G'],&
         file=reg(file))
  end subroutine solve_Htop_new



  !+------------------------------------------------------------------+
  !Auxilliary functions
  !+------------------------------------------------------------------+


 
  !SET THE BATH DELTA FUNCTION

  function set_delta(freq,vps,eps) result(DELTA)
    complex(8),allocatable,dimension(:,:,:,:,:,:)               :: DELTA ![Nlat][Nlat][Nspin][Nspin][Norb][Norb]
    complex(8)                                                  :: freq
    real(8),dimension(:)                                        :: vps,eps
    integer                                                     :: ispin,iorb,ilat
    !
    allocate(DELTA(Nlat,Nlat,Nspin,Nspin,Norb,Norb))
    DELTA=zero
    !
    if (Nbath .ne. 0)then
      do ilat=1,Nlat
        do ispin=1,Nspin
           do iorb=1,Norb
             DELTA(ilat,ilat,ispin,ispin,iorb,iorb)=sum( vps(:)*vps(:)/(freq - eps(:)+XMU) )
           enddo
        enddo
      enddo
    endif
  end function set_delta

  function indices2N(indices) result(N)
    integer,dimension(Ndim)      :: indices
    integer                      :: N,i
    !
    !
    N=1
    N=N+(indices(1)-1)*Ny+(indices(2)-1)
  end function indices2N

  function N2indices(N_) result(indices)
    integer,dimension(Ndim)      :: indices
    integer                      :: N,i,N_
    !
    N=N_-1
    indices(2)=mod(N,Ny)+1
    indices(1)=N/Ny+1
  end function N2indices



end program vca_bhz_2d








